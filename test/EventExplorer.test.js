const EventExplorer = artifacts.require("EventExplorer");
const ParentEventContract = artifacts.require("ParentEventContract");
const ArtistContract = artifacts.require("ArtistContract");
const assert = require('assert');

contract("EventExplorer", function (accounts) {
    const [owner, eventOrganizer, artist, venue, attendee] = accounts;
    let explorer;
    let eventContract;
    let artistContract;

    beforeEach(async () => {
        // Deploy contracts
        explorer = await EventExplorer.new();
        // Deploy ParentEventContract with owner as artist factory (for testing)
        eventContract = await ParentEventContract.new(owner);
        artistContract = await ArtistContract.new(eventContract.address, artist);

        // Setup event details
        await eventContract.setTicketingDetails(100, web3.utils.toWei("0.1", "ether"), false);
    });

    describe("Event Registration", () => {
        it("should register event correctly", async () => {
            await explorer.registerEvent(eventContract.address);
            assert(await explorer.isEventRegistered(eventContract.address), "Event not registered");
        });

        it("should store correct ticket details", async () => {
            await explorer.registerEvent(eventContract.address);
            const details = await explorer.getEventDetails(eventContract.address);

            assert.equal(details.totalTickets, 100, "Wrong ticket supply");
            assert.equal(details.remainingTickets, 100, "Wrong remaining tickets");
            assert.equal(details.currentPrice, web3.utils.toWei("0.1", "ether"), "Wrong ticket price");
        });

        it("should prevent duplicate registration", async () => {
            await explorer.registerEvent(eventContract.address);
            try {
                await explorer.registerEvent(eventContract.address);
                assert.fail("Should not allow duplicate registration");
            } catch (error) {
                assert(error.message.includes("Event already registered"), "Wrong error message");
            }
        });
    });

    describe("Status Management", () => {
        beforeEach(async () => {
            await explorer.registerEvent(eventContract.address);
        });

        it("should update event status", async () => {
            await explorer.updateEventStatus(eventContract.address, 1); // Set to Ongoing
            const details = await explorer.getEventDetails(eventContract.address);
            assert.equal(details.status, 1, "Status not updated");
        });

        it("should update artist status", async () => {
            await explorer.updateArtistStatus(eventContract.address, artistContract.address, 1); // Set to Replaced
            const status = await explorer.getArtistStatus(eventContract.address, artistContract.address);
            assert.equal(status, 1, "Artist status not updated");
        });
    });

    describe("Private Data Access", () => {
        beforeEach(async () => {
            await explorer.registerEvent(eventContract.address, { from: eventOrganizer });
        });

        it("should allow authorized access to private data", async () => {
            await explorer.updateArtistRevenue(eventContract.address, artist, web3.utils.toWei("1", "ether"));
            const revenue = await explorer.getPrivateEventData(eventContract.address, artist, { from: eventOrganizer });
            assert.equal(revenue.toString(), web3.utils.toWei("1", "ether"), "Wrong revenue amount");
        });

        it("should prevent unauthorized access to private data", async () => {
            try {
                await explorer.getPrivateEventData(eventContract.address, artist, { from: attendee });
                assert.fail("Should not allow unauthorized access");
            } catch (error) {
                assert(error.message.includes("Not authorized"), "Wrong error message");
            }
        });

        it("should allow adding new authorized viewers", async () => {
            await explorer.addAuthorizedViewer(eventContract.address, venue, { from: eventOrganizer });
            const isAuthorized = await explorer.isAuthorizedViewer(eventContract.address, venue);
            assert(isAuthorized, "Viewer not authorized");
        });
    });

    describe("Ticket Management", () => {
        beforeEach(async () => {
            await explorer.registerEvent(eventContract.address);
        });

        it("should update ticket availability", async () => {
            await explorer.updateTicketAvailability(eventContract.address, 90);
            const details = await explorer.getEventDetails(eventContract.address);
            assert.equal(details.remainingTickets, 90, "Ticket availability not updated");
        });

        it("should update current price", async () => {
            const newPrice = web3.utils.toWei("0.2", "ether");
            await explorer.updateCurrentPrice(eventContract.address, newPrice);
            const details = await explorer.getEventDetails(eventContract.address);
            assert.equal(details.currentPrice.toString(), newPrice, "Price not updated");
        });
    });
});