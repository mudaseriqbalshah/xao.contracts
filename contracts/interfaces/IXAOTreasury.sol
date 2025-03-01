// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IXAOTreasury {
    // Core events
    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event TransactionProposed(uint256 indexed txId, address indexed proposer, address indexed target, uint256 value, bytes data);
    event TransactionConfirmed(uint256 indexed txId, address indexed signer);
    event TransactionExecuted(uint256 indexed txId);
    event TransactionCancelled(uint256 indexed txId);
    event MinSignersUpdated(uint256 newMinSigners);

    // Treasury events
    event ProfitDistributed(uint256 amount, uint256 timestamp);
    event TokenAdded(address indexed token, uint256 timelockThreshold);
    event TokenRemoved(address indexed token);
    event EmergencyPaused(address indexed pauser);
    event EmergencyUnpaused(address indexed unpauser);
    event TimelockParametersUpdated(uint256 threshold, uint256 period);
    event TransactionTimelocked(uint256 indexed txId, uint256 executionTime);

    // View functions
    function isConfirmedBySigner(uint256 txId, address signer) external view returns (bool);
    function getTransaction(uint256 txId) external view returns (
        address proposer,
        address target,
        uint256 value,
        bytes memory data,
        bool executed,
        uint256 numConfirmations
    );
    function getSigners() external view returns (address[] memory);
    function validateSigner(address signer) external view returns (bool);
    function getMinSigners() external view returns (uint256);
    function getPendingTransactions() external view returns (uint256[] memory);
    function getUnclaimedShare(address staker) external view returns (uint256);

    // Transaction management
    function proposeTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        address token,
        uint256 tokenAmount
    ) external returns (uint256);
    function confirmTransaction(uint256 txId) external;
    function executeTransaction(uint256 txId) external;
    function cancelTransaction(uint256 txId) external;

    // Signer management
    function addSigner(address newSigner) external;
    function removeSigner(address signer) external;
    function updateMinSigners(uint256 newMinSigners) external;

    // Asset management
    function addSupportedToken(address token, uint256 timelockThreshold) external;
    function removeSupportedToken(address token) external;
    function updateTimelockParameters(uint256 newThreshold, uint256 newPeriod) external;

    // Emergency controls
    function pause() external;
    function unpause() external;

    // Treasury operations
    function distributeProfit() external;
    function withdrawShare() external;
}