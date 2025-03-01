const ParentEventContract = artifacts.require("ParentEventContract");
const ArtistContract = artifacts.require("ArtistContract");
const EventFactory = artifacts.require("EventFactory");
const ArtistFactory = artifacts.require("ArtistFactory");
const assert = require('assert');

contract("Factories", function (accounts) {
  const [owner, creator, artist] = accounts;
  let eventFactory, artistFactory;
  const eventFee = web3.utils.toWei("0.1", "ether");

  beforeEach(async () => {
    // Deploy ArtistFactory first
    artistFactory = await ArtistFactory.new();

    // Deploy EventFactory with fee and ArtistFactory address
    eventFactory = await EventFactory.new(eventFee, artistFactory.address);

    // Set EventFactory in ArtistFactory
    await artistFactory.setEventFactory(eventFactory.address);
  });

  describe("EventFactory", () => {
    it("should create an event with correct fee", async () => {
      const initialBalance = await web3.eth.getBalance(eventFactory.address);

      await eventFactory.createEvent({ 
        from: creator, 
        value: eventFee 
      });

      const events = await eventFactory.getEvents(0, 0);
      assert.equal(events.length, 1, "Event not created");

      const finalBalance = await web3.eth.getBalance(eventFactory.address);
      assert.equal(
        finalBalance - initialBalance,
        eventFee,
        "Fee not collected correctly"
      );
    });

    it("should fail with insufficient fee", async () => {
      try {
        await eventFactory.createEvent({ 
          from: creator, 
          value: web3.utils.toWei("0.05", "ether") 
        });
        assert.fail("Should have thrown error for insufficient fee");
      } catch (error) {
        assert(error.message.includes("Insufficient fee"), "Wrong error message");
      }
    });
  });

  describe("ArtistFactory", () => {
    let eventContract;
    let eventContractInstance;

    beforeEach(async () => {
      const result = await eventFactory.createEvent({ 
        from: creator, 
        value: eventFee 
      });
      const events = await eventFactory.getEvents(0, 0);
      eventContract = events[0];

      // Get the deployed event contract instance
      eventContractInstance = await ParentEventContract.at(eventContract);
    });

    it("should create and link artist contract", async () => {
      await artistFactory.createArtistContract(eventContract, artist);

      const artistContracts = await artistFactory.getEventArtists(eventContract);
      assert.equal(artistContracts.length, 1, "Artist not created");

      const isLinked = await eventContractInstance.isArtistLinked(artistContracts[0]);
      assert(isLinked, "Artist not linked to event");
    });

    it("should fail with invalid event contract", async () => {
      try {
        await artistFactory.createArtistContract(accounts[5], artist);
        assert.fail("Should have thrown error for invalid event");
      } catch (error) {
        assert(error.message.includes("Invalid event contract"), "Wrong error message");
      }
    });
  });
});