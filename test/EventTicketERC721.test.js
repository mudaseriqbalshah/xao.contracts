const EventTicketERC721 = artifacts.require("EventTicketERC721");
const XAOReputation = artifacts.require("XAOReputation");
const { expectEvent, expectRevert } = require("@openzeppelin/test-helpers");

contract("EventTicketERC721", function(accounts) {
    const [admin, minter, buyer1, buyer2, reseller] = accounts;
    let ticketContract, reputation;
    const eventId = 1;
    const seatNumber = 100;
    const price = web3.utils.toWei("0.1", "ether");

    beforeEach(async () => {
        // Deploy XAOReputation first (with mock governance)
        reputation = await XAOReputation.new(admin);
        
        // Deploy ticket contract
        ticketContract = await EventTicketERC721.new(reputation.address);
        
        // Grant minter role
        await ticketContract.grantRole(
            await ticketContract.MINTER_ROLE(),
            minter
        );
    });

    describe("Ticket Minting", () => {
        it("should mint tickets correctly", async () => {
            const tx = await ticketContract.mintTicket(
                buyer1,
                eventId,
                seatNumber,
                price,
                true,
                { from: minter }
            );

            expectEvent(tx, "TicketMinted", {
                to: buyer1,
                eventId: web3.utils.toBN(eventId)
            });

            const tokenId = 0; // First ticket
            const owner = await ticketContract.ownerOf(tokenId);
            assert.equal(owner, buyer1, "Wrong ticket owner");

            const ticketInfo = await ticketContract.getTicketInfo(tokenId);
            assert.equal(ticketInfo.seatNumber.toString(), seatNumber.toString(), "Wrong seat number");
            assert.equal(ticketInfo.price.toString(), price.toString(), "Wrong price");
            assert.equal(ticketInfo.resellable, true, "Wrong resale status");
        });

        it("should fail minting from non-minter", async () => {
            await expectRevert(
                ticketContract.mintTicket(buyer1, eventId, seatNumber, price, true, { from: buyer2 }),
                "AccessControl"
            );
        });
    });

    describe("Resale Restrictions", () => {
        let tokenId;

        beforeEach(async () => {
            const tx = await ticketContract.mintTicket(
                buyer1,
                eventId,
                seatNumber,
                price,
                true,
                { from: minter }
            );
            tokenId = 0; // First ticket
        });

        it("should allow transfer of resellable ticket", async () => {
            await ticketContract.approve(buyer2, tokenId, { from: buyer1 });
            await ticketContract.transferFrom(buyer1, buyer2, tokenId, { from: buyer1 });
            
            const newOwner = await ticketContract.ownerOf(tokenId);
            assert.equal(newOwner, buyer2, "Transfer failed");
        });

        it("should block transfer of non-resellable ticket", async () => {
            await ticketContract.setResaleStatus(tokenId, false, { from: admin });
            
            await ticketContract.approve(buyer2, tokenId, { from: buyer1 });
            await expectRevert(
                ticketContract.transferFrom(buyer1, buyer2, tokenId, { from: buyer1 }),
                "Transfer not allowed"
            );
        });
    });

    describe("Royalties", () => {
        it("should return correct royalty info", async () => {
            const salePrice = web3.utils.toWei("1", "ether");
            const royaltyInfo = await ticketContract.royaltyInfo(0, salePrice);

            // Default 5% royalty
            const expectedRoyalty = web3.utils.toBN(salePrice).mul(web3.utils.toBN(500)).div(web3.utils.toBN(10000));
            assert.equal(royaltyInfo.royaltyAmount.toString(), expectedRoyalty.toString(), "Wrong royalty amount");
            assert.equal(royaltyInfo.receiver, admin, "Wrong royalty receiver");
        });

        it("should update royalty percentage", async () => {
            const newPercentage = 300; // 3%
            await ticketContract.setRoyaltyPercentage(newPercentage, { from: admin });

            const salePrice = web3.utils.toWei("1", "ether");
            const royaltyInfo = await ticketContract.royaltyInfo(0, salePrice);

            const expectedRoyalty = web3.utils.toBN(salePrice).mul(web3.utils.toBN(newPercentage)).div(web3.utils.toBN(10000));
            assert.equal(royaltyInfo.royaltyAmount.toString(), expectedRoyalty.toString(), "Royalty not updated");
        });
    });
});