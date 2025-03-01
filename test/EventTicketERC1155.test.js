const EventTicketERC1155 = artifacts.require("EventTicketERC1155");
const XAOReputation = artifacts.require("XAOReputation");
const { expectEvent, expectRevert } = require("@openzeppelin/test-helpers");

contract("EventTicketERC1155", function(accounts) {
    const [admin, minter, buyer1, buyer2, reseller] = accounts;
    let ticketContract, reputation;
    const uri = "https://api.xao.com/ticket/{id}";
    const tierName = "VIP";
    const price = web3.utils.toWei("0.1", "ether");
    const maxSupply = 100;

    beforeEach(async () => {
        // Deploy XAOReputation first (with mock governance)
        reputation = await XAOReputation.new(admin);
        
        // Deploy ticket contract
        ticketContract = await EventTicketERC1155.new(uri, reputation.address);
        
        // Grant minter role
        await ticketContract.grantRole(
            await ticketContract.MINTER_ROLE(),
            minter
        );
    });

    describe("Tier Management", () => {
        it("should create tier correctly", async () => {
            const tx = await ticketContract.createTier(
                tierName,
                price,
                maxSupply,
                { from: minter }
            );

            expectEvent(tx, "TierCreated", {
                name: tierName,
                price: web3.utils.toBN(price),
                maxSupply: web3.utils.toBN(maxSupply)
            });

            const tierId = 0; // First tier
            const tierInfo = await ticketContract.getTierInfo(tierId);
            assert.equal(tierInfo.name, tierName, "Wrong tier name");
            assert.equal(tierInfo.price.toString(), price.toString(), "Wrong price");
            assert.equal(tierInfo.maxSupply.toString(), maxSupply.toString(), "Wrong max supply");
            assert.equal(tierInfo.active, true, "Tier should be active");
        });

        it("should fail creating tier from non-minter", async () => {
            await expectRevert(
                ticketContract.createTier(tierName, price, maxSupply, { from: buyer1 }),
                "AccessControl"
            );
        });
    });

    describe("Ticket Minting", () => {
        let tierId;

        beforeEach(async () => {
            const tx = await ticketContract.createTier(
                tierName,
                price,
                maxSupply,
                { from: minter }
            );
            tierId = 0; // First tier
        });

        it("should mint tickets correctly", async () => {
            const amount = 5;
            const tx = await ticketContract.mintTickets(
                buyer1,
                tierId,
                amount,
                { from: minter }
            );

            expectEvent(tx, "TicketsMinted", {
                tierId: web3.utils.toBN(tierId),
                to: buyer1,
                amount: web3.utils.toBN(amount)
            });

            const balance = await ticketContract.balanceOf(buyer1, tierId);
            assert.equal(balance.toString(), amount.toString(), "Wrong balance");

            const tierInfo = await ticketContract.getTierInfo(tierId);
            assert.equal(tierInfo.currentSupply.toString(), amount.toString(), "Wrong current supply");
        });

        it("should enforce max supply", async () => {
            await expectRevert(
                ticketContract.mintTickets(buyer1, tierId, maxSupply + 1, { from: minter }),
                "Exceeds max supply"
            );
        });
    });

    describe("Transfer Restrictions", () => {
        let tierId;

        beforeEach(async () => {
            await ticketContract.createTier(tierName, price, maxSupply, { from: minter });
            tierId = 0;
            await ticketContract.mintTickets(buyer1, tierId, 10, { from: minter });
        });

        it("should allow transfer when tier is active", async () => {
            const amount = 5;
            await ticketContract.safeTransferFrom(
                buyer1,
                buyer2,
                tierId,
                amount,
                "0x",
                { from: buyer1 }
            );

            const balance = await ticketContract.balanceOf(buyer2, tierId);
            assert.equal(balance.toString(), amount.toString(), "Transfer failed");
        });

        it("should block transfer when tier is inactive", async () => {
            await ticketContract.setTierStatus(tierId, false, { from: admin });

            await expectRevert(
                ticketContract.safeTransferFrom(
                    buyer1,
                    buyer2,
                    tierId,
                    5,
                    "0x",
                    { from: buyer1 }
                ),
                "Transfer not allowed"
            );
        });
    });

    describe("Royalties", () => {
        let tierId;

        beforeEach(async () => {
            await ticketContract.createTier(tierName, price, maxSupply, { from: minter });
            tierId = 0;
        });

        it("should calculate correct royalty", async () => {
            const salePrice = web3.utils.toWei("1", "ether");
            const royalty = await ticketContract.calculateRoyalty(tierId, salePrice);
            
            // 5% royalty
            const expectedRoyalty = web3.utils.toBN(salePrice).mul(web3.utils.toBN(500)).div(web3.utils.toBN(10000));
            assert.equal(royalty.toString(), expectedRoyalty.toString(), "Wrong royalty calculation");
        });
    });
});
