const XAOReputation = artifacts.require("XAOReputation");
const XAOGovernance = artifacts.require("XAOGovernance");
const { time } = require("@openzeppelin/test-helpers");
const assert = require('assert');

contract("XAOReputation", function(accounts) {
    const [owner, manager, user1, user2] = accounts;
    let reputation, governance;
    const Domain = {
        Development: 0,
        Community: 1,
        Governance: 2,
        Marketing: 3
    };

    beforeEach(async () => {
        governance = await XAOGovernance.new(owner, owner); // Mock addresses for token and staking
        reputation = await XAOReputation.new(governance.address);
    });

    describe("Role Management", () => {
        it("should initialize with correct roles", async () => {
            assert(await reputation.hasRole(await reputation.DEFAULT_ADMIN_ROLE(), owner), "Owner should have admin role");
            assert(await reputation.hasRole(await reputation.REPUTATION_MANAGER_ROLE(), owner), "Owner should have manager role");
        });

        it("should allow admin to grant manager role", async () => {
            await reputation.grantReputationManager(manager);
            assert(await reputation.hasRole(await reputation.REPUTATION_MANAGER_ROLE(), manager), "Manager role not granted");
        });
    });

    describe("Reputation Updates", () => {
        beforeEach(async () => {
            await reputation.grantReputationManager(manager);
        });

        it("should update reputation score", async () => {
            const score = 5000; // 50.00
            await reputation.updateReputation(user1, Domain.Development, score, { from: manager });
            const newScore = await reputation.getReputation(user1, Domain.Development);
            assert.equal(newScore.toString(), score.toString(), "Score not updated correctly");
        });

        it("should fail update from non-manager", async () => {
            try {
                await reputation.updateReputation(user1, Domain.Development, 5000, { from: user2 });
                assert.fail("Should have thrown error");
            } catch (error) {
                assert(error.message.includes("reputation manager"), "Wrong error message");
            }
        });

        it("should handle score limits", async () => {
            try {
                await reputation.updateReputation(user1, Domain.Development, 10001, { from: manager });
                assert.fail("Should have thrown error");
            } catch (error) {
                assert(error.message.includes("exceeds maximum"), "Wrong error message");
            }
        });
    });

    describe("Reputation Decay", () => {
        beforeEach(async () => {
            await reputation.grantReputationManager(manager);
            await reputation.updateReputation(user1, Domain.Development, 10000, { from: manager });
        });

        it("should apply monthly decay", async () => {
            // Advance time by one month
            await time.increase(time.duration.days(30));
            
            // Get score after decay
            const score = await reputation.getReputation(user1, Domain.Development);
            const expectedScore = 9500; // 5% decay from 10000
            assert.equal(score.toString(), expectedScore.toString(), "Decay not applied correctly");
        });

        it("should compound decay over multiple periods", async () => {
            // Advance time by three months
            await time.increase(time.duration.days(90));
            
            // Get score after decay
            const score = await reputation.getReputation(user1, Domain.Development);
            // Expected: 10000 * (0.95^3) ≈ 8574
            assert(score.lt(web3.utils.toBN(8600)), "Decay not compounded correctly");
            assert(score.gt(web3.utils.toBN(8500)), "Decay too aggressive");
        });
    });

    describe("Batch Operations", () => {
        beforeEach(async () => {
            await reputation.grantReputationManager(manager);
        });

        it("should update multiple scores in batch", async () => {
            const users = [user1, user2];
            const domains = [Domain.Development, Domain.Marketing];
            const scores = [5000, 6000];

            await reputation.batchUpdateReputation(users, domains, scores, { from: manager });

            const score1 = await reputation.getReputation(user1, Domain.Development);
            const score2 = await reputation.getReputation(user2, Domain.Marketing);

            assert.equal(score1.toString(), "5000", "First score not updated");
            assert.equal(score2.toString(), "6000", "Second score not updated");
        });

        it("should fail batch update with mismatched arrays", async () => {
            const users = [user1, user2];
            const domains = [Domain.Development];
            const scores = [5000, 6000];

            try {
                await reputation.batchUpdateReputation(users, domains, scores, { from: manager });
                assert.fail("Should have thrown error");
            } catch (error) {
                assert(error.message.includes("Array lengths mismatch"), "Wrong error message");
            }
        });
    });
});
