// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IXAOTreasury.sol";
import "./XAOStaking.sol";
import "./XAOGovernance.sol";

/// @title XAO Treasury Contract
/// @author XAO Protocol Team
/// @notice This contract manages the XAO protocol's treasury operations
/// @dev Implements multi-sig functionality, timelock mechanisms, and profit distribution
contract XAOTreasury is IXAOTreasury, Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Information about supported tokens and their timelock thresholds
    /// @dev Struct for storing token-specific parameters
    struct TokenInfo {
        bool isSupported;
        uint256 timelockThreshold;
    }

    /// @notice Details of a proposed transaction
    /// @dev Includes all necessary transaction parameters and confirmation status
    struct Transaction {
        address proposer;
        address target;
        uint256 value;
        bytes data;
        bool executed;
        uint256 numConfirmations;
        uint256 proposedTime;
        bool isTimelocked;
        address token;           /// Address of ERC20 token (address(0) for ETH)
        uint256 tokenAmount;     /// Amount of tokens to transfer
        mapping(address => bool) isConfirmed;
    }

    /// @notice Information about profit distribution
    /// @dev Tracks profit sharing details and claims
    struct ProfitShare {
        uint256 totalAmount;
        uint256 perStakeAmount;
        mapping(address => bool) claimed;
    }

    XAOStaking public xaoStaking;
    XAOGovernance public xaoGovernance;
    uint256 public minSigners;
    uint256 public transactionCount;
    uint256 public profitDistributionCount;

    /// @notice Timelock parameters for transaction execution
    uint256 public timelockThreshold;    /// Amount that triggers timelock for ETH
    uint256 public timelockPeriod;       /// Delay period for timelocked transactions
    uint256 public constant MAX_TIMELOCK = 7 days;
    uint256 public constant MIN_TIMELOCK = 1 days;

    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => ProfitShare) public profitShares;
    mapping(address => bool) public isValidSigner;
    mapping(address => TokenInfo) public supportedTokens;
    address[] public signers;

    /// @notice Constants for governance parameters
    uint256 public constant MAX_SIGNERS = 10;
    uint256 public constant MIN_SIGNERS_REQUIRED = 2;

    /// @notice Restricts function access to valid signers only
    modifier onlySigner() {
        require(isValidSigner[msg.sender], "Not a valid signer");
        _;
    }

    /// @notice Ensures transaction exists
    modifier txExists(uint256 txId) {
        require(txId < transactionCount, "Transaction does not exist");
        _;
    }

    /// @notice Ensures transaction hasn't been executed
    modifier notExecuted(uint256 txId) {
        require(!transactions[txId].executed, "Transaction already executed");
        _;
    }

    /// @notice Ensures signer hasn't already confirmed
    modifier notConfirmed(uint256 txId) {
        require(!transactions[txId].isConfirmed[msg.sender], "Already confirmed");
        _;
    }

    /// @notice Initializes the treasury contract
    /// @dev Sets up initial signers and links to staking and governance contracts
    /// @param _xaoStaking Address of the XAO staking contract
    /// @param _xaoGovernance Address of the XAO governance contract
    /// @param initialSigners Array of initial signer addresses
    /// @param _minSigners Minimum number of signers required for execution
    constructor(
        address _xaoStaking,
        address _xaoGovernance,
        address[] memory initialSigners,
        uint256 _minSigners
    ) {
        require(_xaoStaking != address(0), "Invalid staking address");
        require(_xaoGovernance != address(0), "Invalid governance address");
        require(
            initialSigners.length >= MIN_SIGNERS_REQUIRED,
            "Insufficient initial signers"
        );
        require(
            initialSigners.length <= MAX_SIGNERS,
            "Max signers exceeded"
        );
        require(
            _minSigners >= MIN_SIGNERS_REQUIRED && _minSigners <= initialSigners.length,
            "Invalid min signers"
        );

        xaoStaking = XAOStaking(_xaoStaking);
        xaoGovernance = XAOGovernance(_xaoGovernance);
        minSigners = _minSigners;

        // Initialize timelock parameters
        timelockThreshold = 1 ether;    // Default: 1 ETH
        timelockPeriod = 1 days;        // Default: 24 hours

        for (uint256 i = 0; i < initialSigners.length; i++) {
            address signer = initialSigners[i];
            require(signer != address(0), "Invalid signer address");
            require(!isValidSigner[signer], "Duplicate signer");

            isValidSigner[signer] = true;
            signers.push(signer);
            emit SignerAdded(signer);
        }
    }

    function pause() external override onlySigner {
        require(
            _isOperationApproved(
                msg.sender,
                address(this),
                abi.encodeWithSignature("pause()")
            ),
            "Not approved by governance"
        );
        _pause();
        emit EmergencyPaused(msg.sender);
    }

    function unpause() external override onlySigner {
        require(
            _isOperationApproved(
                msg.sender,
                address(this),
                abi.encodeWithSignature("unpause()")
            ),
            "Not approved by governance"
        );
        _unpause();
        emit EmergencyUnpaused(msg.sender);
    }

    function proposeTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        address token,
        uint256 tokenAmount
    ) external override whenNotPaused onlySigner returns (uint256) {
        require(target != address(0), "Invalid target address");
        if (token != address(0)) {
            require(supportedTokens[token].isSupported, "Token not supported");
        }

        uint256 txId = transactionCount;
        Transaction storage transaction = transactions[txId];
        transaction.proposer = msg.sender;
        transaction.target = target;
        transaction.value = value;
        transaction.data = data;
        transaction.executed = false;
        transaction.numConfirmations = 0;
        transaction.proposedTime = block.timestamp;
        transaction.token = token;
        transaction.tokenAmount = tokenAmount;

        // Check timelock based on token or ETH value
        if (token != address(0)) {
            transaction.isTimelocked = tokenAmount >= supportedTokens[token].timelockThreshold;
        } else {
            transaction.isTimelocked = value >= timelockThreshold;
        }

        transactionCount = transactionCount.add(1);

        if (transaction.isTimelocked) {
            emit TransactionTimelocked(txId, block.timestamp + timelockPeriod);
        }
        emit TransactionProposed(txId, msg.sender, target, value, data);
        return txId;
    }

    function confirmTransaction(uint256 txId)
        external
        override
        onlySigner
        txExists(txId)
        notExecuted(txId)
        notConfirmed(txId)
    {
        Transaction storage transaction = transactions[txId];
        transaction.isConfirmed[msg.sender] = true;
        transaction.numConfirmations = transaction.numConfirmations.add(1);

        emit TransactionConfirmed(txId, msg.sender);
    }

    function executeTransaction(uint256 txId)
        external
        override
        whenNotPaused
        onlySigner
        txExists(txId)
        notExecuted(txId)
    {
        Transaction storage transaction = transactions[txId];
        require(
            transaction.numConfirmations >= minSigners,
            "Insufficient confirmations"
        );

        if (transaction.isTimelocked) {
            require(
                block.timestamp >= transaction.proposedTime + timelockPeriod,
                "Timelock period not elapsed"
            );
        }

        transaction.executed = true;

        // Handle ERC20 token transfer if specified
        if (transaction.token != address(0)) {
            IERC20(transaction.token).safeTransfer(
                transaction.target,
                transaction.tokenAmount
            );
        }

        // Handle ETH transfer if value > 0
        if (transaction.value > 0) {
            (bool success, ) = transaction.target.call{value: transaction.value}(
                transaction.data
            );
            require(success, "ETH transfer failed");
        }

        emit TransactionExecuted(txId);
    }

    function cancelTransaction(uint256 txId)
        external
        override
        onlySigner
        txExists(txId)
        notExecuted(txId)
    {
        Transaction storage transaction = transactions[txId];
        require(
            transaction.proposer == msg.sender,
            "Only proposer can cancel"
        );

        transaction.executed = true; // Mark as executed to prevent further confirmations
        emit TransactionCancelled(txId);
    }

    function addSigner(address newSigner)
        external
        override
        onlySigner
    {
        require(newSigner != address(0), "Invalid signer address");
        require(!isValidSigner[newSigner], "Already a signer");
        require(signers.length < MAX_SIGNERS, "Max signers reached");

        require(
            _isOperationApproved(
                msg.sender,
                address(this),
                abi.encodeWithSignature("addSigner(address)", newSigner)
            ),
            "Not approved by governance"
        );

        isValidSigner[newSigner] = true;
        signers.push(newSigner);
        emit SignerAdded(newSigner);
    }

    function removeSigner(address signer)
        external
        override
        onlySigner
    {
        require(isValidSigner[signer], "Not a signer");
        require(signers.length > minSigners, "Cannot remove signer");

        require(
            _isOperationApproved(
                msg.sender,
                address(this),
                abi.encodeWithSignature("removeSigner(address)", signer)
            ),
            "Not approved by governance"
        );

        isValidSigner[signer] = false;
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == signer) {
                signers[i] = signers[signers.length - 1];
                signers.pop();
                break;
            }
        }
        emit SignerRemoved(signer);
    }

    function updateMinSigners(uint256 newMinSigners)
        external
        override
        onlySigner
    {
        require(
            newMinSigners >= MIN_SIGNERS_REQUIRED && newMinSigners <= signers.length,
            "Invalid min signers"
        );

        require(
            _isOperationApproved(
                msg.sender,
                address(this),
                abi.encodeWithSignature("updateMinSigners(uint256)", newMinSigners)
            ),
            "Not approved by governance"
        );

        minSigners = newMinSigners;
        emit MinSignersUpdated(newMinSigners);
    }

    function addSupportedToken(address token, uint256 _timelockThreshold)
        external
        override
        onlySigner
    {
        require(token != address(0), "Invalid token address");
        require(!supportedTokens[token].isSupported, "Token already supported");
        require(
            _isOperationApproved(
                msg.sender,
                address(this),
                abi.encodeWithSignature("addSupportedToken(address,uint256)", token, _timelockThreshold)
            ),
            "Not approved by governance"
        );

        supportedTokens[token] = TokenInfo({
            isSupported: true,
            timelockThreshold: _timelockThreshold
        });
        emit TokenAdded(token, _timelockThreshold);
    }

    function removeSupportedToken(address token)
        external
        override
        onlySigner
    {
        require(supportedTokens[token].isSupported, "Token not supported");
        require(
            _isOperationApproved(
                msg.sender,
                address(this),
                abi.encodeWithSignature("removeSupportedToken(address)", token)
            ),
            "Not approved by governance"
        );

        delete supportedTokens[token];
        emit TokenRemoved(token);
    }

    function updateTimelockParameters(uint256 newThreshold, uint256 newPeriod)
        external
        override
        onlySigner
    {
        require(
            _isOperationApproved(
                msg.sender,
                address(this),
                abi.encodeWithSignature("updateTimelockParameters(uint256,uint256)", newThreshold, newPeriod)
            ),
            "Not approved by governance"
        );
        require(newPeriod >= MIN_TIMELOCK && newPeriod <= MAX_TIMELOCK, "Invalid timelock period");

        timelockThreshold = newThreshold;
        timelockPeriod = newPeriod;
        emit TimelockParametersUpdated(newThreshold, newPeriod);
    }

    function distributeProfit()
        external
        override
        onlySigner
        nonReentrant
    {
        uint256 balance = address(this).balance;
        require(balance > 0, "No profit to distribute");

        uint256 totalStaked = xaoStaking.totalStaked();
        require(totalStaked > 0, "No stakers");

        uint256 profitId = profitDistributionCount;
        ProfitShare storage share = profitShares[profitId];
        share.totalAmount = balance;
        share.perStakeAmount = balance.mul(1e18).div(totalStaked); // Scale by 1e18 for precision

        profitDistributionCount = profitDistributionCount.add(1);
        emit ProfitDistributed(balance, block.timestamp);
    }

    function withdrawShare()
        external
        override
        nonReentrant
    {
        uint256 share = getUnclaimedShare(msg.sender);
        require(share > 0, "No unclaimed share");

        uint256 profitId = profitDistributionCount.sub(1);
        ProfitShare storage distribution = profitShares[profitId];
        distribution.claimed[msg.sender] = true;

        (bool success, ) = msg.sender.call{value: share}("");
        require(success, "Transfer failed");
    }

    function getUnclaimedShare(address staker)
        public
        view
        override
        returns (uint256)
    {
        if (profitDistributionCount == 0) return 0;

        uint256 profitId = profitDistributionCount.sub(1);
        ProfitShare storage share = profitShares[profitId];
        if (share.claimed[staker]) return 0;

        (uint256 stakedAmount,,) = xaoStaking.getStakeInfo(staker);
        return stakedAmount.mul(share.perStakeAmount).div(1e18);
    }

    function isConfirmedBySigner(uint256 txId, address signer)
        external
        view
        override
        returns (bool)
    {
        return transactions[txId].isConfirmed[signer];
    }

    function getTransaction(uint256 txId)
        external
        view
        override
        returns (
            address proposer,
            address target,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 numConfirmations
        )
    {
        Transaction storage transaction = transactions[txId];
        return (
            transaction.proposer,
            transaction.target,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.numConfirmations
        );
    }

    function getSigners()
        external
        view
        override
        returns (address[] memory)
    {
        return signers;
    }

    function validateSigner(address signer)
        external
        view
        override
        returns (bool)
    {
        return isValidSigner[signer];
    }

    function getMinSigners()
        external
        view
        override
        returns (uint256)
    {
        return minSigners;
    }

    function getPendingTransactions()
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256[] memory pending = new uint256[](transactionCount);
        uint256 count = 0;

        for (uint256 i = 0; i < transactionCount; i++) {
            if (!transactions[i].executed) {
                pending[count] = i;
                count++;
            }
        }

        // Resize array to actual count
        assembly {
            mstore(pending, count)
        }

        return pending;
    }

    function _isOperationApproved(
        address proposer,
        address target,
        bytes memory data
    ) internal view returns (bool) {
        try xaoGovernance.hasRole(keccak256("ADMIN_ROLE"), proposer) returns (bool hasRole) {
            return hasRole;
        } catch {
            return false;
        }
    }

    receive() external payable {}
}