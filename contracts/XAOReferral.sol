// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./XAOToken.sol";

/**
 * @title XAOReferral
 * @dev A contract managing AI-verified referrals and engagement-based rewards in the XAO ecosystem.
 * Features:
 * - AI-powered referral verification
 * - DAO approval system for verified referrals
 * - Engagement-based reward bonuses
 * - Double-claim prevention
 */
contract XAOReferral is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;

    struct ReferralData {
        address referrer;              // Address of the referrer (zero if none)
        uint256 joinTimestamp;         // When the user joined
        bool hasClaimedReward;         // Whether referral reward was claimed
        uint256 engagementScore;       // Current engagement level
        uint256 lastEngagementUpdate;  // Last time engagement was updated
        bool isVerified;               // Whether AI has verified the referral
        bool isApproved;               // Whether DAO has approved the referral
        string verificationData;       // AI verification metadata/results
    }

    // Core token contract
    XAOToken public xaoToken;

    // Reward parameters (adjustable by DAO)
    uint256 public referralReward;          // Base reward for referrals
    uint256 public engagementMultiplier;    // Multiplier for engagement score (100 = 1x)
    uint256 public minimumEngagement;       // Minimum score needed for rewards
    uint256 public cooldownPeriod;          // Time between engagement updates

    // Storage
    mapping(address => ReferralData) public referrals;
    mapping(address => address[]) public referredUsers;
    mapping(address => bool) public isRegistered;

    // Events for tracking and indexing
    event ReferralRegistered(
        address indexed user,
        address indexed referrer,
        uint256 timestamp
    );
    event RewardClaimed(
        address indexed user,
        address indexed referrer,
        uint256 amount
    );
    event EngagementUpdated(
        address indexed user,
        uint256 newScore,
        uint256 timestamp
    );
    event RewardParametersUpdated(
        uint256 newReferralReward,
        uint256 newEngagementMultiplier
    );
    event ReferralVerified(
        address indexed user,
        address indexed referrer,
        bool verified,
        string verificationData
    );
    event ReferralApproved(
        address indexed user,
        address indexed referrer,
        bool approved
    );

    /**
     * @dev Initialize contract with XAO token and default parameters
     * @param _xaoToken Address of the XAO token contract
     */
    constructor(address _xaoToken) {
        require(_xaoToken != address(0), "Invalid token address");
        xaoToken = XAOToken(_xaoToken);

        // Initialize with default parameters
        referralReward = 100 * 10**18;        // 100 XAO tokens
        engagementMultiplier = 100;           // Base multiplier (no bonus)
        minimumEngagement = 5;                // Minimum 5 engagement points
        cooldownPeriod = 1 days;              // 24 hours between updates
    }

    modifier onlyRegistered() {
        require(isRegistered[msg.sender], "User not registered");
        _;
    }

    /**
     * @dev Register a new user with optional referrer
     * @param referrer Address of the referrer (zero address if none)
     * @param verificationData AI verification metadata/results
     * Requirements:
     * - User must not be already registered
     * - Cannot self-refer
     * - Referrer must be registered (if provided)
     */
    function register(address referrer, string calldata verificationData) external whenNotPaused {
        require(!isRegistered[msg.sender], "Already registered");
        require(msg.sender != referrer, "Cannot self-refer");
        require(
            referrer == address(0) || isRegistered[referrer],
            "Invalid referrer"
        );

        isRegistered[msg.sender] = true;
        referrals[msg.sender] = ReferralData({
            referrer: referrer,
            joinTimestamp: block.timestamp,
            hasClaimedReward: false,
            engagementScore: 0,
            lastEngagementUpdate: block.timestamp,
            isVerified: false,
            isApproved: false,
            verificationData: verificationData
        });

        if (referrer != address(0)) {
            referredUsers[referrer].push(msg.sender);
        }

        emit ReferralRegistered(msg.sender, referrer, block.timestamp);
    }

    /**
     * @dev Update AI verification status for a referral
     * @param user Address of the referred user
     * @param verified Whether the referral is verified by AI
     * @param verificationData Updated AI verification metadata
     * Requirements:
     * - Only owner can update
     * - User must be registered
     */
    function updateVerificationStatus(
        address user,
        bool verified,
        string calldata verificationData
    ) external onlyOwner {
        require(isRegistered[user], "User not registered");
        ReferralData storage data = referrals[user];

        data.isVerified = verified;
        data.verificationData = verificationData;

        emit ReferralVerified(user, data.referrer, verified, verificationData);
    }

    /**
     * @dev Approve or reject an AI-verified referral
     * @param user Address of the referred user
     * @param approved Whether to approve the referral
     * Requirements:
     * - Only owner (DAO) can approve
     * - Referral must be AI-verified first
     */
    function approveReferral(address user, bool approved) external onlyOwner {
        require(isRegistered[user], "User not registered");
        ReferralData storage data = referrals[user];
        require(data.isVerified, "Not verified by AI");

        data.isApproved = approved;
        emit ReferralApproved(user, data.referrer, approved);
    }

    /**
     * @dev Claim referral reward for referring a user
     * @param user Address of the referred user
     * Requirements:
     * - Must be the referrer
     * - Reward must not be already claimed
     * - User must have minimum engagement
     * - Referral must be verified by AI and approved by DAO
     * Security:
     * - Uses SafeMath for calculations
     * - Nonreentrant to prevent double claims
     * - Marks claimed before transfer
     */
    function claimReferralReward(address user) external nonReentrant whenNotPaused {
        ReferralData storage data = referrals[user];
        require(data.referrer == msg.sender, "Not the referrer");
        require(!data.hasClaimedReward, "Reward already claimed");
        require(
            data.engagementScore >= minimumEngagement,
            "Insufficient engagement"
        );
        require(data.isVerified, "Referral not verified by AI");
        require(data.isApproved, "Referral not approved by DAO");

        // Calculate reward with engagement bonus (each point = 1% bonus)
        uint256 baseAmount = referralReward;
        uint256 bonusAmount = baseAmount.mul(data.engagementScore).div(100);
        uint256 totalReward = baseAmount.add(bonusAmount);

        // Mark as claimed before transfer to prevent reentrancy
        data.hasClaimedReward = true;
        require(
            xaoToken.transfer(msg.sender, totalReward),
            "Reward transfer failed"
        );

        emit RewardClaimed(user, msg.sender, totalReward);
    }

    /**
     * @dev Update user's engagement score
     * @param user Address of the user
     * @param points Engagement points to add
     * Requirements:
     * - Only owner can update
     * - User must be registered
     * - Cooldown period must have elapsed
     */
    function updateEngagement(address user, uint256 points)
        external
        onlyOwner
        whenNotPaused
    {
        require(isRegistered[user], "User not registered");
        ReferralData storage data = referrals[user];
        require(
            block.timestamp >= data.lastEngagementUpdate.add(cooldownPeriod),
            "Cooldown period not elapsed"
        );

        data.engagementScore = data.engagementScore.add(points);
        data.lastEngagementUpdate = block.timestamp;

        emit EngagementUpdated(user, data.engagementScore, block.timestamp);
    }

    /**
     * @dev Update reward parameters (DAO only)
     * @param newReferralReward New base reward amount
     * @param newEngagementMultiplier New engagement multiplier
     * Requirements:
     * - Only owner can update
     * - Parameters must be valid
     */
    function updateRewardParameters(
        uint256 newReferralReward,
        uint256 newEngagementMultiplier
    ) external onlyOwner {
        require(newReferralReward > 0, "Invalid reward amount");
        require(
            newEngagementMultiplier >= 100,
            "Invalid multiplier"
        );

        referralReward = newReferralReward;
        engagementMultiplier = newEngagementMultiplier;

        emit RewardParametersUpdated(newReferralReward, newEngagementMultiplier);
    }

    // View functions
    function getReferrerCount(address user) external view returns (uint256) {
        return referredUsers[user].length;
    }

    function getReferredUsers(address user) external view returns (address[] memory) {
        return referredUsers[user];
    }

    function getReferralData(address user)
        external
        view
        returns (
            address referrer,
            uint256 joinTimestamp,
            bool hasClaimedReward,
            uint256 engagementScore,
            bool isVerified,
            bool isApproved,
            string memory verificationData
        )
    {
        ReferralData storage data = referrals[user];
        return (
            data.referrer,
            data.joinTimestamp,
            data.hasClaimedReward,
            data.engagementScore,
            data.isVerified,
            data.isApproved,
            data.verificationData
        );
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}