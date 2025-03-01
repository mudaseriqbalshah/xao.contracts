// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./XAOGovernance.sol";

contract XAOReputation is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    // Domain types matching governance domains
    enum Domain { Development, Community, Governance, Marketing }

    struct ReputationScore {
        uint256 score;
        uint256 lastUpdateTime;
        bool initialized;
    }

    // Constants
    uint256 public constant MONTHLY_DECAY_RATE = 5; // 5% monthly decay
    uint256 public constant DECAY_PERIOD = 30 days;
    uint256 public constant MAX_SCORE = 10000; // Max reputation score (100.00)
    uint256 public constant SCALE_FACTOR = 100; // For percentage calculations

    // State variables
    XAOGovernance public xaoGovernance;
    mapping(address => mapping(Domain => ReputationScore)) public reputationScores;

    // Role definitions
    bytes32 public constant REPUTATION_MANAGER_ROLE = keccak256("REPUTATION_MANAGER_ROLE");

    // Events
    event ReputationUpdated(address indexed user, Domain domain, uint256 newScore, uint256 timestamp);
    event ReputationDecayed(address indexed user, Domain domain, uint256 oldScore, uint256 newScore);
    event ReputationManagerGranted(address indexed account);
    event ReputationManagerRevoked(address indexed account);

    constructor(address _xaoGovernance) {
        require(_xaoGovernance != address(0), "Invalid governance address");
        xaoGovernance = XAOGovernance(_xaoGovernance);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(REPUTATION_MANAGER_ROLE, msg.sender);
    }

    modifier onlyReputationManager() {
        require(hasRole(REPUTATION_MANAGER_ROLE, msg.sender), "Caller is not a reputation manager");
        _;
    }

    function updateReputation(
        address user,
        Domain domain,
        uint256 newScore
    ) public onlyReputationManager {
        require(user != address(0), "Invalid user address");
        require(newScore <= MAX_SCORE, "Score exceeds maximum");

        ReputationScore storage reputation = reputationScores[user][domain];

        if (!reputation.initialized) {
            reputation.initialized = true;
        } else {
            // Apply decay before updating
            _applyDecay(user, domain);
        }

        reputation.score = newScore;
        reputation.lastUpdateTime = block.timestamp;

        emit ReputationUpdated(user, domain, newScore, block.timestamp);
    }

    function getReputation(address user, Domain domain) external view returns (uint256) {
        ReputationScore storage reputation = reputationScores[user][domain];

        if (!reputation.initialized) {
            return 0;
        }

        // Calculate decay if time has passed but don't update state
        uint256 timePassed = block.timestamp.sub(reputation.lastUpdateTime);
        uint256 decayPeriods = timePassed.div(DECAY_PERIOD);

        if (decayPeriods == 0) {
            return reputation.score;
        }

        uint256 currentScore = reputation.score;
        for (uint256 i = 0; i < decayPeriods; i++) {
            currentScore = currentScore.mul(SCALE_FACTOR.sub(MONTHLY_DECAY_RATE)).div(SCALE_FACTOR);
        }

        return currentScore;
    }

    function _applyDecay(address user, Domain domain) internal {
        ReputationScore storage reputation = reputationScores[user][domain];
        uint256 timePassed = block.timestamp.sub(reputation.lastUpdateTime);
        uint256 decayPeriods = timePassed.div(DECAY_PERIOD);

        if (decayPeriods > 0) {
            uint256 oldScore = reputation.score;
            uint256 newScore = oldScore;

            for (uint256 i = 0; i < decayPeriods; i++) {
                newScore = newScore.mul(SCALE_FACTOR.sub(MONTHLY_DECAY_RATE)).div(SCALE_FACTOR);
            }

            reputation.score = newScore;
            reputation.lastUpdateTime = block.timestamp;

            emit ReputationDecayed(user, domain, oldScore, newScore);
        }
    }

    // Admin functions for role management
    function grantReputationManager(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(REPUTATION_MANAGER_ROLE, account);
        emit ReputationManagerGranted(account);
    }

    function revokeReputationManager(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(REPUTATION_MANAGER_ROLE, account);
        emit ReputationManagerRevoked(account);
    }

    // Batch operations for efficiency
    function batchUpdateReputation(
        address[] calldata users,
        Domain[] calldata domains,
        uint256[] calldata scores
    ) external onlyReputationManager {
        require(
            users.length == domains.length && domains.length == scores.length,
            "Array lengths mismatch"
        );

        for (uint256 i = 0; i < users.length; i++) {
            updateReputation(users[i], domains[i], scores[i]);
        }
    }
}