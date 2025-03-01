// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./XAOToken.sol";
import "./XAOStaking.sol";

/// @title XAO Governance Contract
/// @author XAO Protocol Team
/// @notice This contract manages the decentralized governance of the XAO protocol
/// @dev Implements role-based access control and proposal management with domain-specific voting
contract XAOGovernance is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    /// @notice The XAO token contract reference
    XAOToken public xaoToken;
    /// @notice The XAO staking contract reference
    XAOStaking public xaoStaking;

    /// @notice Role definitions for access control
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    /// @notice Domain types for specialized voting power
    /// @dev Different domains can have different voting weights
    enum Domain { General, Development, Community, Marketing, Treasury }

    /// @notice Structure defining a governance proposal
    /// @dev Includes all necessary information about a proposal and its voting status
    struct Proposal {
        string description;     /// @dev Description of the proposal
        uint256 proposalDate;   /// @dev When the proposal was created
        uint256 votingEnds;     /// @dev When voting period ends
        address proposer;       /// @dev Address that created the proposal
        Domain domain;         /// @dev Domain category of the proposal
        uint256 requiredStake;  /// @dev Minimum stake required to create proposal
        uint256 forVotes;       /// @dev Total votes in favor
        uint256 againstVotes;   /// @dev Total votes against
        bool executed;         /// @dev Whether the proposal has been executed
        mapping(address => bool) hasVoted; /// @dev Track who has voted
    }

    /// @notice Duration of the voting period
    uint256 public constant VOTING_PERIOD = 7 days;
    /// @notice Minimum stake required to create a proposal
    uint256 public constant MIN_PROPOSAL_STAKE = 1000 * 10**18; // 1000 XAO tokens
    /// @notice Multiplier for domain expertise in voting power
    uint256 public constant DOMAIN_BONUS_MULTIPLIER = 160; // 60% bonus

    /// @notice Total number of proposals created
    uint256 public proposalCount;
    /// @notice Mapping of proposal IDs to proposal details
    mapping(uint256 => Proposal) public proposals;
    /// @notice Mapping of user addresses to their domain-specific reputation
    mapping(address => mapping(Domain => uint256)) public domainReputation;

    /// @notice Emitted when a new proposal is created
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, Domain domain);
    /// @notice Emitted when a vote is cast on a proposal
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    /// @notice Emitted when a proposal is executed
    event ProposalExecuted(uint256 indexed proposalId);
    /// @notice Emitted when a user's reputation in a domain is updated
    event ReputationUpdated(address indexed user, Domain domain, uint256 newReputation);

    /// @notice Initializes the governance contract
    /// @dev Sets up initial roles and connects to XAO token and staking contracts
    /// @param _xaoToken Address of the XAO token contract
    /// @param _xaoStaking Address of the XAO staking contract
    constructor(address _xaoToken, address _xaoStaking) {
        xaoToken = XAOToken(_xaoToken);
        xaoStaking = XAOStaking(_xaoStaking);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(PROPOSER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(EXECUTOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(TREASURY_ROLE, ADMIN_ROLE);
    }

    /// @notice Creates a new proposal
    /// @dev Requires proposer to have sufficient stake and appropriate role
    /// @param description Description of the proposal
    /// @param domain Domain category of the proposal
    /// @return ID of the created proposal
    function createProposal(
        string memory description,
        Domain domain
    ) external onlyRole(PROPOSER_ROLE) returns (uint256) {
        require(
            xaoToken.balanceOf(msg.sender) >= MIN_PROPOSAL_STAKE,
            "Insufficient stake"
        );

        uint256 proposalId = proposalCount++;
        Proposal storage newProposal = proposals[proposalId];
        newProposal.description = description;
        newProposal.proposalDate = block.timestamp;
        newProposal.votingEnds = block.timestamp + VOTING_PERIOD;
        newProposal.proposer = msg.sender;
        newProposal.domain = domain;
        newProposal.requiredStake = MIN_PROPOSAL_STAKE;

        require(
            xaoToken.transferFrom(msg.sender, address(this), MIN_PROPOSAL_STAKE),
            "Stake transfer failed"
        );

        emit ProposalCreated(proposalId, msg.sender, domain);
        return proposalId;
    }

    /// @notice Casts a vote on a proposal
    /// @dev Takes into account user's voting power and domain expertise
    /// @param proposalId ID of the proposal
    /// @param support Whether the vote is in favor or against
    function castVote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp < proposal.votingEnds, "Voting ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");

        uint256 votingPower = _calculateVotingPower(msg.sender, proposal.domain);
        require(votingPower > 0, "No voting power");

        if (support) {
            proposal.forVotes = proposal.forVotes.add(votingPower);
        } else {
            proposal.againstVotes = proposal.againstVotes.add(votingPower);
        }

        proposal.hasVoted[msg.sender] = true;
        emit VoteCast(proposalId, msg.sender, support, votingPower);
    }

    /// @notice Executes a successful proposal
    /// @dev Can only be called by executor role after voting period ends
    /// @param proposalId ID of the proposal to execute
    function executeProposal(uint256 proposalId) external onlyRole(EXECUTOR_ROLE) {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.votingEnds, "Voting not ended");
        require(!proposal.executed, "Already executed");
        require(proposal.forVotes > proposal.againstVotes, "Proposal rejected");

        proposal.executed = true;
        require(
            xaoToken.transfer(proposal.proposer, proposal.requiredStake),
            "Stake return failed"
        );

        emit ProposalExecuted(proposalId);
    }

    /// @notice Updates a user's reputation in a specific domain
    /// @dev Can only be called by admin role
    /// @param user Address of the user
    /// @param domain Domain to update reputation for
    /// @param amount New reputation amount
    function updateDomainReputation(
        address user,
        Domain domain,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        domainReputation[user][domain] = amount;
        emit ReputationUpdated(user, domain, amount);
    }

    /// @notice Calculates a user's voting power for a specific domain
    /// @dev Includes domain expertise bonus if applicable
    /// @param voter Address of the voter
    /// @param domain Domain to calculate voting power for
    /// @return Total voting power including any domain bonuses
    function _calculateVotingPower(
        address voter,
        Domain domain
    ) internal view returns (uint256) {
        uint256 baseVotingPower = xaoStaking.getVotingPower(voter);

        if (domainReputation[voter][domain] > 0) {
            uint256 bonus = baseVotingPower.mul(DOMAIN_BONUS_MULTIPLIER.sub(100)).div(100);
            return baseVotingPower.add(bonus);
        }

        return baseVotingPower;
    }

    /// @notice Retrieves details of a specific proposal
    /// @param proposalId ID of the proposal
    /// @return description Description of the proposal
    /// @return votingEnds End time of voting period
    /// @return proposer Address of the proposer
    /// @return domain Domain category of the proposal
    /// @return forVotes Total votes in favor
    /// @return againstVotes Total votes against
    /// @return executed Whether the proposal has been executed
    function getProposal(uint256 proposalId)
        external
        view
        returns (
            string memory description,
            uint256 votingEnds,
            address proposer,
            Domain domain,
            uint256 forVotes,
            uint256 againstVotes,
            bool executed
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.description,
            proposal.votingEnds,
            proposal.proposer,
            proposal.domain,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.executed
        );
    }
}