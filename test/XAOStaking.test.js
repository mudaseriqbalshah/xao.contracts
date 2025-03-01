const XAOToken = artifacts.require("XAOToken");
const XAOStaking = artifacts.require("XAOStaking");
const { time } = require("@openzeppelin/test-helpers");
const assert = require('assert');

contract("XAOStaking", function(accounts) {
    const [owner, user1, user2] = accounts;
    let token, staking;
    const stakeAmount = web3.utils.toWei("1000", "ether");

    beforeEach(async () => {
        token = await XAOToken.new();
        staking = await XAOStaking.new(token.address);

        // Transfer tokens to users for testing
        await token.transfer(user1, web3.utils.toWei("10000", "ether"));
        await token.transfer(user2, web3.utils.toWei("10000", "ether"));

        // Approve staking contract to spend tokens
        await token.approve(staking.address, stakeAmount, { from: user1 });
    });

    describe("Staking", () => {
        it("should allow staking tokens", async () => {
            await staking.stake(stakeAmount, { from: user1 });
            const stakeInfo = await staking.getStakeInfo(user1);
            assert.equal(stakeInfo.amount.toString(), stakeAmount, "Wrong stake amount");
        });

        it("should update total staked amount", async () => {
            await staking.stake(stakeAmount, { from: user1 });
            const totalStaked = await staking.totalStaked();
            assert.equal(totalStaked.toString(), stakeAmount, "Wrong total staked");
        });

        it("should prevent staking when paused", async () => {
            await staking.pause({ from: owner });
            try {
                await staking.stake(stakeAmount, { from: user1 });
                assert.fail("Should not allow staking when paused");
            } catch (error) {
                assert(error.message.includes("paused"), "Wrong error message");
            }
        });
    });

    describe("Reward Distribution", () => {
        beforeEach(async () => {
            await token.approve(staking.address, stakeAmount, { from: user1 });
            await staking.stake(stakeAmount, { from: user1 });
        });

        it("should calculate rewards correctly", async () => {
            // Advance time by one quarter (90 days)
            await time.increase(time.duration.days(90));

            const rewards = await staking.calculateRewards(user1);
            const expectedRewards = web3.utils.toBN(stakeAmount)
                .mul(web3.utils.toBN(5)) // 5% reward rate
                .div(web3.utils.toBN(100));

            assert.equal(rewards.toString(), expectedRewards.toString(), "Wrong reward calculation");
        });

        it("should not allow claiming rewards before full cycle", async () => {
            await time.increase(time.duration.days(45)); // Half cycle

            const rewards = await staking.calculateRewards(user1);
            assert.equal(rewards.toString(), "0", "Should not accrue rewards before full cycle");
        });
    });

    describe("Withdrawal Restrictions", () => {
        beforeEach(async () => {
            await token.approve(staking.address, stakeAmount, { from: user1 });
            await staking.stake(stakeAmount, { from: user1 });
            await time.advanceBlock();
        });

        it("should apply penalty for early withdrawal", async () => {
            const initialBalance = web3.utils.toBN(await token.balanceOf(user1));
            const withdrawalAmount = web3.utils.toBN(stakeAmount);
            const penalty = withdrawalAmount.mul(web3.utils.toBN(10)).div(web3.utils.toBN(100)); // 10%
            const expectedReceived = withdrawalAmount.sub(penalty);

            await staking.withdraw(stakeAmount, { from: user1 });
            const finalBalance = web3.utils.toBN(await token.balanceOf(user1));
            const actualReceived = finalBalance.sub(initialBalance);

            assert.equal(
                actualReceived.toString(),
                expectedReceived.toString(),
                "Wrong withdrawal amount"
            );
        });

        it("should not apply penalty after minimum duration", async () => {
            await time.increase(time.duration.days(91)); // Past minimum stake duration

            const initialBalance = web3.utils.toBN(await token.balanceOf(user1));
            await staking.withdraw(stakeAmount, { from: user1 });
            const finalBalance = web3.utils.toBN(await token.balanceOf(user1));

            assert.equal(
                finalBalance.sub(initialBalance).toString(),
                stakeAmount.toString(),
                "Should not include penalty"
            );
        });
    });

    describe("Security Controls", () => {
        it("should allow owner to pause/unpause", async () => {
            await staking.pause({ from: owner });
            assert(await staking.paused(), "Contract not paused");

            await staking.unpause({ from: owner });
            assert(!(await staking.paused()), "Contract still paused");
        });

        it("should prevent non-owner from pausing", async () => {
            try {
                await staking.pause({ from: user1 });
                assert.fail("Should not allow non-owner to pause");
            } catch (error) {
                assert(error.message.includes("Ownable:"), "Wrong error message");
            }
        });
    });
});