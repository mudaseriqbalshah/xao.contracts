const XAOToken = artifacts.require("XAOToken");
const XAOGovernance = artifacts.require("XAOGovernance");
const { time } = require("@openzeppelin/test-helpers");
const assert = require('assert');

contract("XAOGovernance", function(accounts) {
    const [owner, proposer, voter1, voter2] = accounts;
    let token, governance;
    const proposalStake = web3.utils.toWei("1000", "ether");
    const voterStake = web3.utils.toWei("10000", "ether");

    beforeEach(async () => {
        // Deploy contracts
        token = await XAOToken.new();
        governance = await XAOGovernance.new(token.address, owner);

        // Grant roles
        const PROPOSER_ROLE = await governance.PROPOSER_ROLE();
        const EXECUTOR_ROLE = await governance.EXECUTOR_ROLE();
        await governance.grantRole(PROPOSER_ROLE, proposer);
        await governance.grantRole(EXECUTOR_ROLE, owner);

        // Transfer tokens to proposer and voters
        await token.transfer(proposer, proposalStake);
        await token.transfer(voter1, voterStake);
        await token.transfer(voter2, voterStake);

        // Approve governance contract to spend tokens
        await token.approve(governance.address, proposalStake, { from: proposer });
        await token.approve(governance.address, voterStake, { from: voter1 });
        await token.approve(governance.address, voterStake, { from: voter2 });
    });

    describe("Role Management", () => {
        it("should have correct role hierarchy", async () => {
            const ADMIN_ROLE = await governance.DEFAULT_ADMIN_ROLE();
            assert(await governance.hasRole(ADMIN_ROLE, owner), "Owner should have admin role");
        });

        it("should allow admin to grant roles", async () => {
            const PROPOSER_ROLE = await governance.PROPOSER_ROLE();
            await governance.grantRole(PROPOSER_ROLE, voter1, { from: owner });
            assert(await governance.hasRole(PROPOSER_ROLE, voter1), "Role should be granted");
        });
    });

    describe("Proposal Creation", () => {
        it("should create proposal with correct stake", async () => {
            const initialBalance = await token.balanceOf(proposer);
            await governance.createProposal("Test Proposal", { from: proposer });
            const finalBalance = await token.balanceOf(proposer);

            assert.equal(
                initialBalance.sub(finalBalance).toString(),
                proposalStake,
                "Wrong stake amount"
            );

            const proposal = await governance.getProposal(0);
            assert.equal(proposal.description, "Test Proposal", "Wrong description");
            assert.equal(proposal.proposer, proposer, "Wrong proposer");
        });

        it("should fail without proposer role", async () => {
            try {
                await governance.createProposal("Test", { from: voter2 });
                assert.fail("Should have thrown error");
            } catch (error) {
                assert(error.message.includes("missing role"), "Wrong error message");
            }
        });
    });

    describe("Voting", () => {
        beforeEach(async () => {
            await governance.createProposal("Test Proposal", { from: proposer });
        });

        it("should allow voting with correct weight", async () => {
            await governance.castVote(0, true, { from: voter1 });
            const proposal = await governance.getProposal(0);
            assert(proposal.forVotes.gt(web3.utils.toBN(0)), "Vote not counted");
        });

        it("should prevent double voting", async () => {
            await governance.castVote(0, true, { from: voter1 });
            try {
                await governance.castVote(0, true, { from: voter1 });
                assert.fail("Should prevent double voting");
            } catch (error) {
                assert(error.message.includes("Already voted"), "Wrong error message");
            }
        });
    });

    describe("Proposal Execution", () => {
        beforeEach(async () => {
            await governance.createProposal("Test Proposal", { from: proposer });
            await governance.castVote(0, true, { from: voter1 });
        });

        it("should execute successful proposal and return stake", async () => {
            await time.increase(time.duration.days(8));
            const initialBalance = await token.balanceOf(proposer);
            await governance.executeProposal(0, { from: owner });
            const finalBalance = await token.balanceOf(proposer);

            assert.equal(
                finalBalance.sub(initialBalance).toString(),
                proposalStake,
                "Stake not returned"
            );

            const proposal = await governance.getProposal(0);
            assert(proposal.executed, "Proposal not marked as executed");
        });

        it("should not execute before voting period ends", async () => {
            try {
                await governance.executeProposal(0, { from: owner });
                assert.fail("Should not execute early");
            } catch (error) {
                assert(error.message.includes("Voting not ended"), "Wrong error message");
            }
        });
    });
});