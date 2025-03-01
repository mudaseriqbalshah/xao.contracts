const XAOToken = artifacts.require("XAOToken");
const XAOReferral = artifacts.require("XAOReferral");
const { time, expectRevert } = require("@openzeppelin/test-helpers");

contract("XAOReferral", function (accounts) {
    const [owner, user1, user2, user3] = accounts;
    let token, referral;
    const referralReward = web3.utils.toWei("100", "ether"); // 100 XAO
    const mockVerificationData = JSON.stringify({
        verified: true,
        confidence: 0.95,
        reasoning: "Test verification data"
    });

    beforeEach(async () => {
        // Deploy contracts
        token = await XAOToken.new();
        referral = await XAOReferral.new(token.address);

        // Fund referral contract with tokens
        await token.transfer(referral.address, web3.utils.toWei("10000", "ether"));
    });

    describe("Registration", () => {
        it("should register without referrer", async () => {
            await referral.register(
                "0x0000000000000000000000000000000000000000",
                mockVerificationData,
                { from: user1 }
            );
            const data = await referral.getReferralData(user1);
            assert.equal(data.isVerified, false, "Should start unverified");
            assert.equal(data.isApproved, false, "Should start unapproved");
        });

        it("should register with valid referrer", async () => {
            await referral.register(
                "0x0000000000000000000000000000000000000000",
                mockVerificationData,
                { from: user1 }
            );
            await referral.register(user1, mockVerificationData, { from: user2 });

            const data = await referral.getReferralData(user2);
            assert.equal(data.referrer, user1, "Wrong referrer");
            assert.equal(data.verificationData, mockVerificationData, "Wrong verification data");
        });

        it("should prevent self-referral", async () => {
            await expectRevert(
                referral.register(user1, mockVerificationData, { from: user1 }),
                "Cannot self-refer"
            );
        });

        it("should prevent double registration", async () => {
            await referral.register(
                "0x0000000000000000000000000000000000000000",
                mockVerificationData,
                { from: user1 }
            );
            await expectRevert(
                referral.register(
                    "0x0000000000000000000000000000000000000000",
                    mockVerificationData,
                    { from: user1 }
                ),
                "Already registered"
            );
        });
    });

    describe("AI Verification Process", () => {
        beforeEach(async () => {
            await referral.register(
                "0x0000000000000000000000000000000000000000",
                mockVerificationData,
                { from: user1 }
            );
            await referral.register(user1, mockVerificationData, { from: user2 });
        });

        it("should allow owner to update verification status", async () => {
            const newVerificationData = JSON.stringify({
                verified: true,
                confidence: 0.98,
                reasoning: "Updated verification"
            });

            await referral.updateVerificationStatus(
                user2, true, newVerificationData,
                { from: owner }
            );

            const data = await referral.getReferralData(user2);
            assert.equal(data.isVerified, true, "Not marked as verified");
            assert.equal(data.verificationData, newVerificationData, "Verification data not updated");
        });

        it("should prevent non-owner from updating verification", async () => {
            await expectRevert(
                referral.updateVerificationStatus(
                    user2, true, mockVerificationData,
                    { from: user1 }
                ),
                "Ownable: caller is not the owner"
            );
        });

        it("should allow DAO to approve verified referral", async () => {
            await referral.updateVerificationStatus(
                user2, true, mockVerificationData,
                { from: owner }
            );
            await referral.approveReferral(user2, true, { from: owner });

            const data = await referral.getReferralData(user2);
            assert.equal(data.isApproved, true, "Not marked as approved");
        });

        it("should prevent approval of unverified referral", async () => {
            await expectRevert(
                referral.approveReferral(user2, true, { from: owner }),
                "Not verified by AI"
            );
        });
    });

    describe("Engagement and Rewards", () => {
        beforeEach(async () => {
            await referral.register(
                "0x0000000000000000000000000000000000000000",
                mockVerificationData,
                { from: user1 }
            );
            await referral.register(user1, mockVerificationData, { from: user2 });

            // Verify and approve the referral
            await referral.updateVerificationStatus(
                user2, true, mockVerificationData,
                { from: owner }
            );
            await referral.approveReferral(user2, true, { from: owner });

            // Add minimum engagement and wait for cooldown
            await time.increase(time.duration.days(1));
        });

        it("should calculate rewards with engagement multiplier", async () => {
            await referral.updateEngagement(user2, 5, { from: owner });
            await time.increase(time.duration.days(1));

            const initialBalance = web3.utils.toBN(await token.balanceOf(user1));
            await referral.claimReferralReward(user2, { from: user1 });
            const finalBalance = web3.utils.toBN(await token.balanceOf(user1));

            // Base reward + 5% bonus (5 engagement points * 1% per point)
            const expectedReward = web3.utils.toBN(referralReward)
                .mul(web3.utils.toBN(105))
                .div(web3.utils.toBN(100));

            assert.equal(
                finalBalance.sub(initialBalance).toString(),
                expectedReward.toString(),
                "Wrong reward amount"
            );
        });

        it("should prevent claiming without verification", async () => {
            await referral.register(user1, mockVerificationData, { from: user3 });
            await referral.updateEngagement(user3, 5, { from: owner });
            await time.increase(time.duration.days(1));

            await expectRevert(
                referral.claimReferralReward(user3, { from: user1 }),
                "Referral not verified by AI"
            );
        });

        it("should prevent claiming without DAO approval", async () => {
            await referral.register(user1, mockVerificationData, { from: user3 });
            await referral.updateVerificationStatus(
                user3, true, mockVerificationData,
                { from: owner }
            );
            await referral.updateEngagement(user3, 5, { from: owner });
            await time.increase(time.duration.days(1));

            await expectRevert(
                referral.claimReferralReward(user3, { from: user1 }),
                "Referral not approved by DAO"
            );
        });
    });

    describe("View Functions", () => {
        beforeEach(async () => {
            await referral.register(
                "0x0000000000000000000000000000000000000000",
                mockVerificationData,
                { from: user1 }
            );
            await referral.register(user1, mockVerificationData, { from: user2 });
            await referral.register(user1, mockVerificationData, { from: user3 });
        });

        it("should track referral counts", async () => {
            const count = await referral.getReferrerCount(user1);
            assert.equal(count.toString(), "2", "Wrong referral count");
        });

        it("should list referred users", async () => {
            const referred = await referral.getReferredUsers(user1);
            assert.equal(referred.length, 2, "Wrong number of referred users");
            assert.equal(referred[0], user2, "Wrong referred user");
            assert.equal(referred[1], user3, "Wrong referred user");
        });

        it("should return complete referral data with verification status", async () => {
            const data = await referral.getReferralData(user2);
            assert.equal(data.referrer, user1, "Wrong referrer");
            assert.equal(data.isVerified, false, "Wrong verification status");
            assert.equal(data.isApproved, false, "Wrong approval status");
            assert.equal(data.verificationData, mockVerificationData, "Wrong verification data");
        });
    });
});