const ParentEventContract = artifacts.require("ParentEventContract");
const ArtistContract = artifacts.require("ArtistContract");
const { time } = require("@openzeppelin/test-helpers");

contract("ArtistContract", function (accounts) {
    const [owner, artist, venue] = accounts;
    let parentContract;
    let artistContract;

    beforeEach(async () => {
        parentContract = await ParentEventContract.new(owner);
        artistContract = await ArtistContract.new(parentContract.address, artist);
    });

    describe("Contract Setup", () => {
        it("should initialize with correct addresses", async () => {
            const details = await artistContract.getArtistDetails();
            assert.equal(details.artist, artist, "Artist address not set correctly");
            assert.equal(details.parentContract, parentContract.address, "Parent contract not set correctly");
        });
    });

    describe("Artist Details", () => {
        it("should set performance details", async () => {
            const now = Math.floor(Date.now() / 1000);
            const loadInTime = now + 86400;
            const setTime = loadInTime + 3600;

            await artistContract.setArtistDetails(
                loadInTime,
                setTime,
                "Technical requirements",
                "Legal terms",
                web3.utils.toWei("1", "ether"),
                15  // 15% revenue share
            );

            const details = await artistContract.getArtistDetails();
            assert.equal(details.loadInTime.toString(), loadInTime.toString(), "Load-in time not set");
            assert.equal(details.setTime.toString(), setTime.toString(), "Set time not set");
        });

        it("should validate time constraints", async () => {
            const now = Math.floor(Date.now() / 1000);
            const setTime = now + 86400;
            const invalidLoadInTime = setTime + 3600; // Load-in after set time

            try {
                await artistContract.setArtistDetails(
                    invalidLoadInTime,
                    setTime,
                    "Requirements",
                    "Terms",
                    web3.utils.toWei("1", "ether"),
                    15
                );
                assert.fail("Should have thrown error for invalid times");
            } catch (error) {
                assert(error.message.includes("Invalid times"), "Wrong error message");
            }
        });
    });

    describe("Cancellation System", () => {
        const guarantee = web3.utils.toWei("1", "ether");
        const deposit = web3.utils.toWei("0.5", "ether");

        beforeEach(async () => {
            const currentTime = await time.latest();
            // Set event 180 days in the future to allow for all test scenarios
            const loadInTime = currentTime.add(time.duration.days(180));
            const setTime = loadInTime.add(time.duration.hours(1));

            await artistContract.setArtistDetails(
                loadInTime.toString(),
                setTime.toString(),
                "Requirements",
                "Terms",
                guarantee,
                15
            );
            await artistContract.signContract({ from: artist });
            await web3.eth.sendTransaction({
                from: artist,
                to: artistContract.address,
                value: deposit
            });
        });

        it("should apply early cancellation penalty", async () => {
            const initialBalance = web3.utils.toBN(await web3.eth.getBalance(artist));
            const tx = await artistContract.cancelPerformance({ from: artist });
            const finalBalance = web3.utils.toBN(await web3.eth.getBalance(artist));

            // Calculate gas cost
            const gasUsed = web3.utils.toBN(tx.receipt.gasUsed);
            const gasPrice = web3.utils.toBN(await web3.eth.getGasPrice());
            const gasCost = gasPrice.mul(gasUsed);

            // Expected refund (90% of deposit - gas costs)
            const refundAmount = web3.utils.toBN(deposit).mul(web3.utils.toBN(90)).div(web3.utils.toBN(100));
            const expectedBalance = initialBalance.add(refundAmount).sub(gasCost);

            assert(finalBalance.gte(expectedBalance.mul(web3.utils.toBN(99)).div(web3.utils.toBN(100))), 
                "Refund amount incorrect");
        });

        it("should apply late cancellation penalty", async () => {
            // Move forward to late cancellation window
            await time.increase(time.duration.days(150));

            const initialBalance = web3.utils.toBN(await web3.eth.getBalance(artist));
            const tx = await artistContract.cancelPerformance({ from: artist });
            const finalBalance = web3.utils.toBN(await web3.eth.getBalance(artist));

            // Calculate gas cost
            const gasUsed = web3.utils.toBN(tx.receipt.gasUsed);
            const gasPrice = web3.utils.toBN(await web3.eth.getGasPrice());
            const gasCost = gasPrice.mul(gasUsed);

            // Expected refund (50% of deposit - gas costs)
            const refundAmount = web3.utils.toBN(deposit).mul(web3.utils.toBN(50)).div(web3.utils.toBN(100));
            const expectedBalance = initialBalance.add(refundAmount).sub(gasCost);

            assert(finalBalance.gte(expectedBalance.mul(web3.utils.toBN(99)).div(web3.utils.toBN(100))), 
                "Refund amount incorrect");
        });

        it("should apply very late cancellation penalty", async () => {
            // Move forward to very late cancellation window
            await time.increase(time.duration.days(175));

            const initialBalance = web3.utils.toBN(await web3.eth.getBalance(artist));
            const tx = await artistContract.cancelPerformance({ from: artist });
            const finalBalance = web3.utils.toBN(await web3.eth.getBalance(artist));

            // Calculate gas cost
            const gasUsed = web3.utils.toBN(tx.receipt.gasUsed);
            const gasPrice = web3.utils.toBN(await web3.eth.getGasPrice());
            const gasCost = gasPrice.mul(gasUsed);

            // Should only pay gas costs (100% penalty)
            const expectedBalance = initialBalance.sub(gasCost);

            assert(finalBalance.lte(expectedBalance), 
                "Should not receive refund for very late cancellation");
        });
    });

    describe("Contract Signing", () => {
        it("should allow artist to sign", async () => {
            await artistContract.signContract({ from: artist });
            const isSigned = await artistContract.isContractSigned();
            assert(isSigned, "Contract not marked as signed");
        });

        it("should prevent non-artist from signing", async () => {
            try {
                await artistContract.signContract({ from: venue });
                assert.fail("Should have thrown error for unauthorized signer");
            } catch (error) {
                assert(error.message.includes("Only artist can call"), "Wrong error message");
            }
        });
    });

    describe("Payment Handling", () => {
        beforeEach(async () => {
            const currentTime = await time.latest();
            const loadInTime = currentTime.add(time.duration.days(1));
            const setTime = loadInTime.add(time.duration.hours(1));

            await artistContract.signContract({ from: artist });
            await artistContract.setArtistDetails(
                loadInTime.toString(),
                setTime.toString(),
                "Requirements",
                "Terms",
                web3.utils.toWei("1", "ether"),
                15
            );
        });

        it("should handle deposits correctly", async () => {
            const deposit = web3.utils.toWei("0.5", "ether");
            await web3.eth.sendTransaction({
                from: artist,
                to: artistContract.address,
                value: deposit
            });

            const details = await artistContract.getArtistDetails();
            assert.equal(
                details.depositAmount.toString(),
                deposit,
                "Deposit amount not recorded correctly"
            );
        });
    });
});