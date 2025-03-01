// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./XAOToken.sol";
import "./XAOGovernance.sol";

contract XAOMarketing is Ownable, ReentrancyGuard, Pausable {
    struct Campaign {
        string name;
        uint256 budget;
        uint256 spent;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isApproved;
        uint256 lastPayoutRequestTime;
        bool inDispute;
    }

    struct Dispute {
        uint256 campaignId;
        address initiator;
        uint256 requestedAmount;
        uint256 filingTime;
        bool evidenceComplete;
        bool aiDecisionIssued;
        bool isAppealed;
        bytes32 evidenceIPFSHash;
        bytes32 aiDecisionIPFSHash;
        uint256 approvedAmount;
        bool isResolved;
    }

    // Constants for time periods
    uint256 public constant EVIDENCE_PERIOD = 5 days;
    uint256 public constant APPEAL_PERIOD = 2 days;
    uint256 public constant TOTAL_DISPUTE_PERIOD = 7 days;

    XAOToken public xaoToken;
    XAOGovernance public xaoGovernance;
    uint256 public minApprovals;
    uint256 public campaignCount;
    uint256 public totalBudget;
    uint256 public spentBudget;
    uint256 public disputeCount;

    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => bool) public campaignHasActiveDispute;

    event CampaignCreated(
        uint256 indexed campaignId,
        string name,
        uint256 budget,
        uint256 startTime,
        uint256 endTime
    );
    event CampaignApproved(uint256 indexed campaignId);
    event PayoutExecuted(
        uint256 indexed campaignId,
        address indexed recipient,
        uint256 amount
    );
    event DisputeFiled(
        uint256 indexed disputeId,
        uint256 indexed campaignId,
        address initiator,
        uint256 requestedAmount
    );
    event EvidenceSubmitted(
        uint256 indexed disputeId,
        bytes32 evidenceIPFSHash
    );
    event AIDecisionIssued(
        uint256 indexed disputeId,
        bytes32 decisionIPFSHash,
        uint256 approvedAmount
    );
    event DisputeAppealed(uint256 indexed disputeId);
    event DisputeResolved(
        uint256 indexed disputeId,
        uint256 finalAmount
    );

    constructor(
        address _xaoToken,
        address _xaoGovernance,
        uint256 _minApprovals
    ) {
        require(_xaoToken != address(0), "Invalid token address");
        require(_xaoGovernance != address(0), "Invalid governance address");
        require(_minApprovals > 0, "Invalid min approvals");

        xaoToken = XAOToken(_xaoToken);
        xaoGovernance = XAOGovernance(_xaoGovernance);
        minApprovals = _minApprovals;
    }

    function initializeBudget(uint256 amount) external onlyOwner {
        require(totalBudget == 0, "Budget already initialized");
        require(amount > 0, "Invalid amount");
        require(
            xaoToken.balanceOf(address(this)) >= amount,
            "Insufficient token balance"
        );
        totalBudget = amount;
    }

    function createCampaign(
        string calldata name,
        uint256 budget,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner whenNotPaused {
        require(bytes(name).length > 0, "Empty name");
        require(budget > 0, "Invalid budget");
        require(budget <= totalBudget - spentBudget, "Insufficient budget");
        require(
            startTime >= block.timestamp && endTime > startTime,
            "Invalid timeframe"
        );

        uint256 campaignId = campaignCount;
        Campaign storage campaign = campaigns[campaignId];

        campaign.name = name;
        campaign.budget = budget;
        campaign.startTime = startTime;
        campaign.endTime = endTime;
        campaign.isActive = false;
        campaign.isApproved = false;
        campaign.spent = 0;
        campaign.lastPayoutRequestTime = 0;
        campaign.inDispute = false;

        campaignCount++;

        emit CampaignCreated(
            campaignId,
            name,
            budget,
            startTime,
            endTime
        );
    }

    function approveCampaign(uint256 campaignId) external onlyOwner whenNotPaused {
        require(campaignId < campaignCount, "Invalid campaign");
        Campaign storage campaign = campaigns[campaignId];
        require(!campaign.isActive, "Already active");

        campaign.isApproved = true;
        campaign.isActive = true;

        emit CampaignApproved(campaignId);
    }

    function requestPayout(
        uint256 campaignId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(campaignId < campaignCount, "Invalid campaign");
        Campaign storage campaign = campaigns[campaignId];
        require(campaign.isActive && campaign.isApproved, "Campaign not active");
        require(!campaign.inDispute, "Campaign in dispute");
        require(amount > 0, "Invalid amount");
        require(amount <= campaign.budget - campaign.spent, "Exceeds budget");

        campaign.lastPayoutRequestTime = block.timestamp;
        campaign.inDispute = true;

        uint256 disputeId = disputeCount++;
        disputes[disputeId] = Dispute({
            campaignId: campaignId,
            initiator: msg.sender,
            requestedAmount: amount,
            filingTime: block.timestamp,
            evidenceComplete: false,
            aiDecisionIssued: false,
            isAppealed: false,
            evidenceIPFSHash: bytes32(0),
            aiDecisionIPFSHash: bytes32(0),
            approvedAmount: 0,
            isResolved: false
        });

        campaignHasActiveDispute[campaignId] = true;

        emit DisputeFiled(disputeId, campaignId, msg.sender, amount);
    }

    function submitEvidence(
        uint256 disputeId,
        bytes32 evidenceHash
    ) external whenNotPaused {
        require(disputeId < disputeCount, "Invalid dispute");
        Dispute storage dispute = disputes[disputeId];
        require(!dispute.evidenceComplete, "Evidence period closed");
        require(
            block.timestamp <= dispute.filingTime + EVIDENCE_PERIOD,
            "Evidence period expired"
        );

        dispute.evidenceIPFSHash = evidenceHash;
        dispute.evidenceComplete = true;

        emit EvidenceSubmitted(disputeId, evidenceHash);
    }

    function submitAIDecision(
        uint256 disputeId,
        bytes32 decisionHash,
        uint256 approvedAmount
    ) external onlyOwner whenNotPaused {
        require(disputeId < disputeCount, "Invalid dispute");
        Dispute storage dispute = disputes[disputeId];
        require(dispute.evidenceComplete, "Evidence not complete");
        require(!dispute.aiDecisionIssued, "Decision already issued");
        require(
            approvedAmount <= dispute.requestedAmount,
            "Amount exceeds request"
        );

        dispute.aiDecisionIPFSHash = decisionHash;
        dispute.approvedAmount = approvedAmount;
        dispute.aiDecisionIssued = true;

        emit AIDecisionIssued(disputeId, decisionHash, approvedAmount);
    }

    function appealDecision(uint256 disputeId) external whenNotPaused {
        require(disputeId < disputeCount, "Invalid dispute");
        Dispute storage dispute = disputes[disputeId];
        require(dispute.aiDecisionIssued, "No decision to appeal");
        require(!dispute.isAppealed, "Already appealed");
        require(
            block.timestamp <= dispute.filingTime + EVIDENCE_PERIOD + APPEAL_PERIOD,
            "Appeal period expired"
        );

        dispute.isAppealed = true;

        emit DisputeAppealed(disputeId);
    }

    function executePayout(
        uint256 disputeId
    ) external nonReentrant whenNotPaused {
        require(disputeId < disputeCount, "Invalid dispute");
        Dispute storage dispute = disputes[disputeId];
        require(dispute.aiDecisionIssued, "No decision issued");
        require(!dispute.isResolved, "Already resolved");
        require(
            block.timestamp > dispute.filingTime + TOTAL_DISPUTE_PERIOD ||
                (dispute.aiDecisionIssued && !dispute.isAppealed),
            "Dispute period not ended"
        );

        Campaign storage campaign = campaigns[dispute.campaignId];
        require(campaign.isActive, "Campaign not active");
        require(
            dispute.approvedAmount <= campaign.budget - campaign.spent,
            "Exceeds campaign budget"
        );

        campaign.spent += dispute.approvedAmount;
        spentBudget += dispute.approvedAmount;
        dispute.isResolved = true;
        campaign.inDispute = false;
        campaignHasActiveDispute[dispute.campaignId] = false;

        require(
            xaoToken.transfer(dispute.initiator, dispute.approvedAmount),
            "Transfer failed"
        );

        emit PayoutExecuted(dispute.campaignId, dispute.initiator, dispute.approvedAmount);
        emit DisputeResolved(disputeId, dispute.approvedAmount);

        if (campaign.spent >= campaign.budget) {
            campaign.isActive = false;
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getCampaign(uint256 campaignId)
        external
        view
        returns (
            string memory name,
            uint256 budget,
            uint256 spent,
            uint256 startTime,
            uint256 endTime,
            bool isActive,
            bool isApproved
        )
    {
        require(campaignId < campaignCount, "Invalid campaign");
        Campaign storage campaign = campaigns[campaignId];
        return (
            campaign.name,
            campaign.budget,
            campaign.spent,
            campaign.startTime,
            campaign.endTime,
            campaign.isActive,
            campaign.isApproved
        );
    }

    function getDispute(uint256 disputeId)
        external
        view
        returns (
            uint256 campaignId,
            address initiator,
            uint256 requestedAmount,
            uint256 filingTime,
            bool evidenceComplete,
            bool aiDecisionIssued,
            bool isAppealed,
            bytes32 evidenceIPFSHash,
            bytes32 aiDecisionIPFSHash,
            uint256 approvedAmount,
            bool isResolved
        )
    {
        require(disputeId < disputeCount, "Invalid dispute");
        Dispute storage dispute = disputes[disputeId];
        return (
            dispute.campaignId,
            dispute.initiator,
            dispute.requestedAmount,
            dispute.filingTime,
            dispute.evidenceComplete,
            dispute.aiDecisionIssued,
            dispute.isAppealed,
            dispute.evidenceIPFSHash,
            dispute.aiDecisionIPFSHash,
            dispute.approvedAmount,
            dispute.isResolved
        );
    }
}