const XAOToken = artifacts.require("XAOToken");
const XAOGovernance = artifacts.require("XAOGovernance");
const XAOMarketing = artifacts.require("XAOMarketing");
const { time } = require("@openzeppelin/test-helpers");
const assert = require('assert');

contract("XAOMarketing", function (accounts) {
    const [owner, recipient, disputer] = accounts;
    let token, governance, marketing;
    const minApprovals = 1;
    const initialBudget = web3.utils.toWei("10000", "ether");

    beforeEach(async () => {
        // Deploy contracts
        token = await XAOToken.new();
        governance = await XAOGovernance.new(token.address, owner);
        marketing = await XAOMarketing.new(
            token.address,
            governance.address,
            minApprovals
        );

        // Fund marketing contract and initialize budget
        await token.transfer(marketing.address, initialBudget);
        await marketing.initializeBudget(initialBudget);
    });

    describe("Campaign Management", () => {
        const campaignName = "Test Campaign";
        const budget = web3.utils.toWei("1000", "ether");

        it("should create campaign with correct parameters", async () => {
            const startTime = (await time.latest()).add(time.duration.days(1));
            const endTime = startTime.add(time.duration.days(30));

            await marketing.createCampaign(
                campaignName,
                budget,
                startTime,
                endTime,
                { from: owner }
            );

            const campaign = await marketing.getCampaign(0);
            assert.equal(campaign.name, campaignName, "Wrong name");
            assert.equal(campaign.budget.toString(), budget, "Wrong budget");
            assert.equal(campaign.isActive, false, "Should start inactive");
            assert.equal(campaign.isApproved, false, "Should start unapproved");
        });
    });

    describe("Arbitration System", () => {
        const campaignName = "Marketing Campaign";
        const budget = web3.utils.toWei("1000", "ether");
        const payoutAmount = web3.utils.toWei("100", "ether");
        let campaignId, startTime, endTime;

        beforeEach(async () => {
            startTime = (await time.latest()).add(time.duration.days(1));
            endTime = startTime.add(time.duration.days(30));

            await marketing.createCampaign(
                campaignName,
                budget,
                startTime,
                endTime,
                { from: owner }
            );

            campaignId = 0;
            await marketing.approveCampaign(campaignId, { from: owner });
            await time.increase(time.duration.days(1)); // Move to campaign start
        });

        it("should initiate dispute and payout process", async () => {
            await marketing.requestPayout(campaignId, payoutAmount, { from: disputer });

            const dispute = await marketing.getDispute(0);
            assert.equal(dispute.campaignId.toString(), campaignId.toString(), "Wrong campaign ID");
            assert.equal(dispute.initiator, disputer, "Wrong initiator");
            assert.equal(dispute.requestedAmount.toString(), payoutAmount, "Wrong amount");
            assert.equal(dispute.isResolved, false, "Should not be resolved");
        });

        it("should handle evidence submission", async () => {
            await marketing.requestPayout(campaignId, payoutAmount, { from: disputer });

            const evidenceHash = web3.utils.keccak256("evidence data");
            await marketing.submitEvidence(0, evidenceHash, { from: disputer });

            const dispute = await marketing.getDispute(0);
            assert.equal(dispute.evidenceComplete, true, "Evidence not marked complete");
            assert.equal(dispute.evidenceIPFSHash, evidenceHash, "Wrong evidence hash");
        });

        it("should process AI decision", async () => {
            await marketing.requestPayout(campaignId, payoutAmount, { from: disputer });

            const evidenceHash = web3.utils.keccak256("evidence data");
            await marketing.submitEvidence(0, evidenceHash, { from: disputer });

            const decisionHash = web3.utils.keccak256("AI decision");
            const approvedAmount = web3.utils.toWei("80", "ether"); // 80% approved
            await marketing.submitAIDecision(0, decisionHash, approvedAmount, { from: owner });

            const dispute = await marketing.getDispute(0);
            assert.equal(dispute.aiDecisionIssued, true, "Decision not marked as issued");
            assert.equal(dispute.approvedAmount.toString(), approvedAmount, "Wrong approved amount");
        });

        it("should allow appeals within window", async () => {
            await marketing.requestPayout(campaignId, payoutAmount, { from: disputer });

            const evidenceHash = web3.utils.keccak256("evidence data");
            await marketing.submitEvidence(0, evidenceHash, { from: disputer });

            const decisionHash = web3.utils.keccak256("AI decision");
            const approvedAmount = web3.utils.toWei("80", "ether");
            await marketing.submitAIDecision(0, decisionHash, approvedAmount, { from: owner });

            await marketing.appealDecision(0, { from: disputer });

            const dispute = await marketing.getDispute(0);
            assert.equal(dispute.isAppealed, true, "Appeal not recorded");
        });

        it("should execute payout after dispute period", async () => {
            await marketing.requestPayout(campaignId, payoutAmount, { from: disputer });

            const evidenceHash = web3.utils.keccak256("evidence data");
            await marketing.submitEvidence(0, evidenceHash, { from: disputer });

            const decisionHash = web3.utils.keccak256("AI decision");
            const approvedAmount = web3.utils.toWei("80", "ether");
            await marketing.submitAIDecision(0, decisionHash, approvedAmount, { from: owner });

            // Wait for dispute period to end
            await time.increase(time.duration.days(7));

            const initialBalance = web3.utils.toBN(await token.balanceOf(disputer));
            await marketing.executePayout(0);
            const finalBalance = web3.utils.toBN(await token.balanceOf(disputer));

            assert.equal(
                finalBalance.sub(initialBalance).toString(),
                approvedAmount,
                "Wrong payout amount"
            );

            const dispute = await marketing.getDispute(0);
            assert.equal(dispute.isResolved, true, "Dispute not marked resolved");
        });

        it("should allow early payout if no appeal", async () => {
            await marketing.requestPayout(campaignId, payoutAmount, { from: disputer });

            const evidenceHash = web3.utils.keccak256("evidence data");
            await marketing.submitEvidence(0, evidenceHash, { from: disputer });

            const decisionHash = web3.utils.keccak256("AI decision");
            const approvedAmount = web3.utils.toWei("80", "ether");
            await marketing.submitAIDecision(0, decisionHash, approvedAmount, { from: owner });

            // Wait only 5 days (after evidence period, before appeal period ends)
            await time.increase(time.duration.days(5));

            const initialBalance = web3.utils.toBN(await token.balanceOf(disputer));
            await marketing.executePayout(0);
            const finalBalance = web3.utils.toBN(await token.balanceOf(disputer));

            assert.equal(
                finalBalance.sub(initialBalance).toString(),
                approvedAmount,
                "Wrong payout amount"
            );
        });
    });
});