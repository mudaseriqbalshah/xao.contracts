// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/// @title XAO Staking Contract
/// @author XAO Protocol Team
/// @notice This contract manages the staking mechanism for XAO tokens
/// @dev Implements staking with time-based reputation, rewards, and early withdrawal penalties
contract XAOStaking is ReentrancyGuard, Ownable, Pausable {
    using SafeMath for uint256;

    /// @notice Interface for the XAO token contract
    IERC20 public xaoToken;

    /// @notice Structure to track individual stake information
    /// @dev Contains stake amount, timestamp, reputation, and reward claim history
    struct Stake {
        uint256 amount;        /// @dev Amount of tokens staked
        uint256 timestamp;     /// @dev Time when the stake was created
        uint256 reputation;    /// @dev Reputation points earned
        uint256 lastRewardClaim; /// @dev Timestamp of last reward claim
    }

    /// @notice Mapping of addresses to their stake information
    mapping(address => Stake) public stakes;

    /// @notice Total amount of tokens staked in the contract
    uint256 public totalStaked;

    /// @notice Minimum duration required for staking without penalty
    /// @dev Set to one quarter (90 days)
    uint256 public constant MIN_STAKE_DURATION = 90 days;

    /// @notice Base multiplier for calculating reputation
    uint256 public constant REPUTATION_MULTIPLIER = 100;

    /// @notice Penalty percentage for early withdrawal (10%)
    uint256 public constant EARLY_WITHDRAWAL_PENALTY = 10;

    /// @notice Quarterly reward rate (5%)
    uint256 public rewardRate = 5;

    /// @notice Emitted when tokens are staked
    /// @param user Address of the staker
    /// @param amount Amount of tokens staked
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted when tokens are withdrawn
    /// @param user Address of the withdrawer
    /// @param amount Amount withdrawn
    /// @param penalty Amount penalized for early withdrawal
    event Withdrawn(address indexed user, uint256 amount, uint256 penalty);

    /// @notice Emitted when reputation is updated
    /// @param user Address of the user
    /// @param newReputation New reputation score
    event ReputationUpdated(address indexed user, uint256 newReputation);

    /// @notice Emitted when rewards are claimed
    /// @param user Address of the claimer
    /// @param amount Amount of rewards claimed
    event RewardsClaimed(address indexed user, uint256 amount);

    /// @notice Emitted when reward rate is updated
    /// @param newRate New reward rate
    event RewardRateUpdated(uint256 newRate);

    /// @notice Initializes the staking contract
    /// @dev Sets up the XAO token interface
    /// @param _xaoToken Address of the XAO token contract
    constructor(address _xaoToken) {
        require(_xaoToken != address(0), "Invalid token address");
        xaoToken = IERC20(_xaoToken);
    }

    /// @notice Pauses all staking operations
    /// @dev Can only be called by the contract owner
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resumes all staking operations
    /// @dev Can only be called by the contract owner
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Stakes tokens in the contract
    /// @dev Transfers tokens from user to contract and updates stake info
    /// @param amount Amount of tokens to stake
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot stake 0");
        require(xaoToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        if (stakes[msg.sender].amount > 0) {
            stakes[msg.sender].amount = stakes[msg.sender].amount.add(amount);
            _updateReputation(msg.sender);
        } else {
            stakes[msg.sender] = Stake({
                amount: amount,
                timestamp: block.timestamp,
                reputation: 0,
                lastRewardClaim: block.timestamp
            });
        }

        totalStaked = totalStaked.add(amount);
        emit Staked(msg.sender, amount);
    }

    /// @notice Withdraws staked tokens
    /// @dev Applies early withdrawal penalty if applicable
    /// @param amount Amount of tokens to withdraw
    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.amount >= amount, "Insufficient stake");

        uint256 penalty = 0;
        if (block.timestamp < userStake.timestamp.add(MIN_STAKE_DURATION)) {
            penalty = amount.mul(EARLY_WITHDRAWAL_PENALTY).div(100);
        }

        uint256 withdrawAmount = amount.sub(penalty);
        userStake.amount = userStake.amount.sub(amount);
        totalStaked = totalStaked.sub(amount);

        if (userStake.amount > 0) {
            _updateReputation(msg.sender);
        } else {
            userStake.reputation = 0;
        }

        if (penalty > 0) {
            require(xaoToken.transfer(owner(), penalty), "Penalty transfer failed");
        }

        require(xaoToken.transfer(msg.sender, withdrawAmount), "Transfer failed");
        emit Withdrawn(msg.sender, amount, penalty);
    }

    /// @notice Calculates rewards for a user
    /// @dev Based on stake amount and time elapsed
    /// @param user Address of the user
    /// @return Amount of rewards available
    function calculateRewards(address user) public view returns (uint256) {
        Stake memory userStake = stakes[user];
        if (userStake.amount == 0) return 0;

        uint256 timeElapsed = block.timestamp.sub(userStake.lastRewardClaim);
        uint256 fullCycles = timeElapsed.div(MIN_STAKE_DURATION);

        if (fullCycles == 0) return 0;

        return userStake.amount
            .mul(rewardRate)
            .mul(fullCycles)
            .div(100);
    }

    /// @notice Claims available rewards
    /// @dev Transfers calculated rewards to user
    function claimRewards() external nonReentrant whenNotPaused {
        uint256 rewards = calculateRewards(msg.sender);
        require(rewards > 0, "No rewards to claim");

        stakes[msg.sender].lastRewardClaim = block.timestamp;
        require(xaoToken.transfer(msg.sender, rewards), "Reward transfer failed");

        emit RewardsClaimed(msg.sender, rewards);
    }

    /// @notice Updates the reward rate
    /// @dev Can only be called by the contract owner
    /// @param newRate New reward rate to set
    function updateRewardRate(uint256 newRate) external onlyOwner {
        require(newRate <= 20, "Rate too high"); // Max 20% quarterly
        rewardRate = newRate;
        emit RewardRateUpdated(newRate);
    }

    /// @notice Updates user's reputation based on stake amount and duration
    /// @dev Internal function to calculate and update reputation
    /// @param user Address of the user
    function _updateReputation(address user) internal {
        Stake storage userStake = stakes[user];
        uint256 stakeDuration = block.timestamp.sub(userStake.timestamp);
        uint256 newReputation = userStake.amount
            .mul(stakeDuration)
            .div(1 days)
            .mul(REPUTATION_MULTIPLIER)
            .div(10000);

        userStake.reputation = newReputation;
        emit ReputationUpdated(user, newReputation);
    }

    /// @notice Gets the voting power of a user
    /// @dev Based on user's reputation
    /// @param user Address of the user
    /// @return User's voting power
    function getVotingPower(address user) external view returns (uint256) {
        return stakes[user].reputation;
    }

    /// @notice Gets detailed stake information for a user
    /// @param user Address of the user
    /// @return amount Amount staked
    /// @return timestamp Time of stake
    /// @return reputation Current reputation score
    function getStakeInfo(address user) external view returns (
        uint256 amount,
        uint256 timestamp,
        uint256 reputation
    ) {
        Stake memory userStake = stakes[user];
        return (userStake.amount, userStake.timestamp, userStake.reputation);
    }
}