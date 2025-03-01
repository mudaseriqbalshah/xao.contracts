const XAOToken = artifacts.require("XAOToken");
const XAOStaking = artifacts.require("XAOStaking");
const XAOGovernance = artifacts.require("XAOGovernance");
const XAOTreasury = artifacts.require("XAOTreasury");
const { time, expectRevert } = require("@openzeppelin/test-helpers");

contract("XAOTreasury", function (accounts) {
    const [owner, signer1, signer2, signer3, signer4, user1] = accounts;
    let token, staking, governance, treasury, testToken;
    const initialSigners = [signer1, signer2, signer3];
    const minSigners = 2;
    const largeAmount = web3.utils.toWei("1.5", "ether"); // Above timelock threshold
    const smallAmount = web3.utils.toWei("0.5", "ether");  // Below timelock threshold

    beforeEach(async () => {
        // Deploy XAO contracts
        token = await XAOToken.new();
        staking = await XAOStaking.new(token.address);
        governance = await XAOGovernance.new(token.address, staking.address);
        treasury = await XAOTreasury.new(
            staking.address,
            governance.address,
            initialSigners,
            minSigners
        );

        // Deploy test ERC20 token
        testToken = await XAOToken.new(); // Using XAOToken as test token

        // Set up roles
        const ADMIN_ROLE = await governance.ADMIN_ROLE();
        const TREASURY_ROLE = await governance.TREASURY_ROLE();
        await governance.grantRole(ADMIN_ROLE, signer1);
        await governance.grantRole(TREASURY_ROLE, treasury.address);

        // Fund treasury with ETH
        await web3.eth.sendTransaction({
            from: owner,
            to: treasury.address,
            value: web3.utils.toWei("5", "ether")
        });

        // Fund treasury with test tokens
        await testToken.transfer(treasury.address, web3.utils.toWei("1000", "ether"));
    });

    describe("Emergency Controls", () => {
        it("should allow pausing by authorized signer", async () => {
            await treasury.pause({ from: signer1 });
            assert(await treasury.paused(), "Contract not paused");

            await expectRevert(
                treasury.proposeTransaction(
                    user1, smallAmount, "0x", 
                    "0x0000000000000000000000000000000000000000", 0, 
                    { from: signer1 }
                ),
                "Pausable: paused"
            );
        });

        it("should allow unpausing by authorized signer", async () => {
            await treasury.pause({ from: signer1 });
            await treasury.unpause({ from: signer1 });
            assert(!(await treasury.paused()), "Contract still paused");

            const tx = await treasury.proposeTransaction(
                user1, smallAmount, "0x", 
                "0x0000000000000000000000000000000000000000", 0, 
                { from: signer1 }
            );
            assert(tx.receipt.status, "Transaction failed");
        });
    });

    describe("Token Support", () => {
        const tokenTimelockThreshold = web3.utils.toWei("100", "ether");

        beforeEach(async () => {
            await treasury.addSupportedToken(testToken.address, tokenTimelockThreshold, { from: signer1 });
        });

        it("should add supported token with correct threshold", async () => {
            const tokenInfo = await treasury.supportedTokens(testToken.address);
            assert.equal(tokenInfo.isSupported, true, "Token not supported");
            assert.equal(tokenInfo.timelockThreshold.toString(), tokenTimelockThreshold, "Wrong threshold");
        });

        it("should execute token transfer transaction", async () => {
            const transferAmount = web3.utils.toWei("10", "ether");
            const tx = await treasury.proposeTransaction(
                user1,
                0,
                "0x",
                testToken.address,
                transferAmount,
                { from: signer1 }
            );

            const txId = tx.logs.find(log => log.event === "TransactionProposed").args.txId;
            await treasury.confirmTransaction(txId, { from: signer2 });
            await treasury.confirmTransaction(txId, { from: signer3 });

            const initialBalance = await testToken.balanceOf(user1);
            await treasury.executeTransaction(txId, { from: signer1 });
            const finalBalance = await testToken.balanceOf(user1);

            assert.equal(
                finalBalance.sub(initialBalance).toString(),
                transferAmount,
                "Token transfer failed"
            );
        });

        it("should enforce token-specific timelock", async () => {
            const largeTokenAmount = web3.utils.toWei("150", "ether"); // Above token threshold
            const tx = await treasury.proposeTransaction(
                user1,
                0,
                "0x",
                testToken.address,
                largeTokenAmount,
                { from: signer1 }
            );

            const txId = tx.logs.find(log => log.event === "TransactionProposed").args.txId;
            await treasury.confirmTransaction(txId, { from: signer2 });
            await treasury.confirmTransaction(txId, { from: signer3 });

            await expectRevert(
                treasury.executeTransaction(txId, { from: signer1 }),
                "Timelock period not elapsed"
            );

            await time.increase(time.duration.days(1));
            await treasury.executeTransaction(txId, { from: signer1 });
        });
        it("should remove supported token", async () => {
            await treasury.removeSupportedToken(testToken.address, { from: signer1 });
            const tokenInfo = await treasury.supportedTokens(testToken.address);
            assert.equal(tokenInfo.isSupported, false, "Token still supported");
        });
    });

    describe("Timelock Functionality", () => {
        it("should require timelock for large transactions", async () => {
            await treasury.updateTimelockParameters(
                web3.utils.toWei("1", "ether"),
                time.duration.days(1),
                { from: signer1 }
            );

            const tx = await treasury.proposeTransaction(
                user1,
                largeAmount,
                "0x",
                "0x0000000000000000000000000000000000000000",
                0,
                { from: signer1 }
            );
            const txId = tx.logs.find(log => log.event === "TransactionProposed").args.txId;

            await treasury.confirmTransaction(txId, { from: signer2 });
            await treasury.confirmTransaction(txId, { from: signer3 });

            await expectRevert(
                treasury.executeTransaction(txId, { from: signer1 }),
                "Timelock period not elapsed"
            );

            await time.increase(time.duration.days(1));
            await treasury.executeTransaction(txId, { from: signer1 });
        });

        it("should allow instant execution for small transactions", async () => {
            const tx = await treasury.proposeTransaction(
                user1,
                smallAmount,
                "0x",
                "0x0000000000000000000000000000000000000000",
                0,
                { from: signer1 }
            );
            const txId = tx.logs.find(log => log.event === "TransactionProposed").args.txId;

            await treasury.confirmTransaction(txId, { from: signer2 });
            await treasury.confirmTransaction(txId, { from: signer3 });
            await treasury.executeTransaction(txId, { from: signer1 });
        });
    });

    describe("Multi-Sig Approvals", () => {
        it("should require minimum signatures for transaction execution", async () => {
            const tx = await treasury.proposeTransaction(
                user1, 
                smallAmount, 
                "0x", 
                "0x0000000000000000000000000000000000000000", 
                0, 
                { from: signer1 }
            );
            const txId = tx.logs.find(log => log.event === "TransactionProposed").args.txId;

            await expectRevert(
                treasury.executeTransaction(txId, { from: signer1 }),
                "Insufficient confirmations"
            );

            await treasury.confirmTransaction(txId, { from: signer2 });
            await treasury.confirmTransaction(txId, { from: signer3 });
            await treasury.executeTransaction(txId, { from: signer1 });
        });

        it("should not allow duplicate confirmations", async () => {
            const tx = await treasury.proposeTransaction(
                user1, 
                smallAmount, 
                "0x", 
                "0x0000000000000000000000000000000000000000", 
                0, 
                { from: signer1 }
            );
            const txId = tx.logs.find(log => log.event === "TransactionProposed").args.txId;

            await treasury.confirmTransaction(txId, { from: signer2 });
            await expectRevert(
                treasury.confirmTransaction(txId, { from: signer2 }),
                "Already confirmed"
            );
        });
    });

    describe("Signer Management", () => {
        it("should add new signer with governance approval", async () => {
            await treasury.addSigner(signer4, { from: signer1 });
            assert(await treasury.validateSigner(signer4), "Signer not added");
        });

        it("should remove signer with governance approval", async () => {
            await treasury.removeSigner(signer3, { from: signer1 });
            assert(!(await treasury.validateSigner(signer3)), "Signer not removed");
        });

        it("should not allow removing signer if it would violate min signers", async () => {
            // First remove one signer (allowed)
            await treasury.removeSigner(signer3, { from: signer1 });

            // Trying to remove another should fail
            await expectRevert(
                treasury.removeSigner(signer2, { from: signer1 }),
                "Cannot remove signer"
            );
        });
    });
    describe("Initial Setup", () => {
        it("should initialize with correct signers", async () => {
            const signers = await treasury.getSigners();
            assert.equal(signers.length, initialSigners.length, "Wrong number of signers");
            assert.equal(await treasury.getMinSigners(), minSigners, "Wrong min signers");
        });

        it("should validate initial parameters", async () => {
            assert.equal(await treasury.xaoStaking(), staking.address, "Wrong staking address");
            assert.equal(await treasury.xaoGovernance(), governance.address, "Wrong governance address");
        });
    });

    describe("Transaction Management", () => {
        let txId;
        const target = user1;
        const value = web3.utils.toWei("0.1", "ether");
        const data = "0x";

        beforeEach(async () => {
            // Create transaction
            const tx = await treasury.proposeTransaction(target, value, data, "0x0000000000000000000000000000000000000000", 0, { from: signer1 });
            txId = tx.logs.find(log => log.event === "TransactionProposed").args.txId;
        });

        it("should allow signers to propose and confirm transactions", async () => {
            await treasury.confirmTransaction(txId, { from: signer2 });
            const transaction = await treasury.getTransaction(txId);
            assert.equal(transaction.numConfirmations, 1, "Wrong confirmation count");
        });

        it("should execute transaction when enough confirmations", async () => {
            await treasury.confirmTransaction(txId, { from: signer2 });
            await treasury.confirmTransaction(txId, { from: signer3 });
            const initialBalance = web3.utils.toBN(await web3.eth.getBalance(target));

            await treasury.executeTransaction(txId, { from: signer1 });

            const finalBalance = web3.utils.toBN(await web3.eth.getBalance(target));
            assert.equal(
                finalBalance.sub(initialBalance).toString(),
                value,
                "Transfer amount incorrect"
            );
        });

        it("should not execute transaction without enough confirmations", async () => {
            await expectRevert(
                treasury.executeTransaction(txId, { from: signer1 }),
                "Insufficient confirmations"
            );
        });
    });

    describe("Profit Distribution", () => {
        it("should distribute profits according to defined rules (placeholder)", async () => {
            // Add test cases for profit distribution based on specific contract implementation
            // This is a placeholder and requires detailed knowledge of profit distribution logic
            assert.ok(true,"Profit distribution test not implemented")
        });
    });
});