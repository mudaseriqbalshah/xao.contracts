const XAOToken = artifacts.require("XAOToken");
const { time } = require("@openzeppelin/test-helpers");
const assert = require('assert');

contract("XAOToken", function(accounts) {
    const [owner, teamMember1, user1] = accounts;
    let token;

    beforeEach(async () => {
        token = await XAOToken.new();
    });

    describe("Initial Setup", () => {
        it("should set correct initial supply", async () => {
            const totalSupply = await token.totalSupply();
            assert.equal(
                totalSupply.toString(),
                web3.utils.toWei("1000000000", "ether"),
                "Wrong initial supply"
            );
        });

        it("should allocate correct team tokens", async () => {
            const contractBalance = await token.balanceOf(owner);
            assert.equal(
                contractBalance.toString(),
                web3.utils.toWei("800000000", "ether"),
                "Wrong team allocation"
            );
        });
    });

    describe("Team Vesting", () => {
        const allocation = web3.utils.toWei("1000000", "ether");

        beforeEach(async () => {
            await token.addTeamMember(teamMember1, allocation, { from: owner });
        });

        it("should not allow claiming before cliff", async () => {
            try {
                await token.claimTeamTokens({ from: teamMember1 });
                assert.fail("Should not allow claiming before cliff");
            } catch (error) {
                assert(error.message.includes("Still in cliff period"));
            }
        });

        it("should allow claiming after cliff", async () => {
            // Move time forward past cliff
            await time.increase(time.duration.years(1));
            await token.claimTeamTokens({ from: teamMember1 });

            const balance = await token.balanceOf(teamMember1);
            assert(balance.gt(web3.utils.toBN(0)), "No tokens claimed");
        });
    });

    describe("Transfer Protection", () => {
        it("should prevent flash loan attacks", async () => {
            const amount = web3.utils.toWei("1000", "ether");
            await token.transfer(user1, amount, { from: owner });

            try {
                await token.transfer(owner, amount, { from: user1 });
                assert.fail("Should not allow immediate transfer");
            } catch (error) {
                assert(error.message.includes("Transfer delay not met"));
            }
        });

        it("should allow transfer after delay", async () => {
            const amount = web3.utils.toWei("1000", "ether");
            await token.transfer(user1, amount, { from: owner });

            // Wait for transfer delay
            await time.increase(time.duration.hours(24));

            // Should now succeed
            await token.transfer(owner, amount, { from: user1 });
            const finalBalance = await token.balanceOf(user1);
            assert.equal(finalBalance.toString(), "0", "Transfer not executed");
        });

        it("should exempt certain addresses from delay", async () => {
            const amount = web3.utils.toWei("1000", "ether");
            await token.setTransferDelayExempt(user1, true, { from: owner });
            await token.transfer(user1, amount, { from: owner });

            // Should succeed immediately
            await token.transfer(owner, amount, { from: user1 });
            const finalBalance = await token.balanceOf(user1);
            assert.equal(finalBalance.toString(), "0", "Transfer not executed");
        });
    });
});