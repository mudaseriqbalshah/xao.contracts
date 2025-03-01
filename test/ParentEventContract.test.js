// SPDX-License-Identifier: MIT
const ParentEventContract = artifacts.require("ParentEventContract");
const { time, BN } = require("@openzeppelin/test-helpers");
const assert = require('assert');

contract("ParentEventContract", function (accounts) {
    const [owner, artist, attendee] = accounts;
    let parentContract;
    const basePrice = web3.utils.toWei("0.1", "ether");
    const maxPrice = web3.utils.toWei("0.2", "ether");
    const minPrice = web3.utils.toWei("0.05", "ether");

    beforeEach(async () => {
        console.log("\nTest Setup - Starting deployment");
        console.log("Owner address:", owner);

        // Deploy with owner as the artist factory for testing
        parentContract = await ParentEventContract.new(owner, { from: owner });
        console.log("Contract deployed at:", parentContract.address);
        console.log("Contract owner:", await parentContract.owner());

        // Get current timestamp
        const latestTime = await time.latest();
        console.log("Current timestamp:", latestTime.toString());

        // Convert to BN and add time periods
        const eventDate = latestTime.add(time.duration.days(180));
        const startTime = eventDate.add(time.duration.hours(1));
        const endTime = startTime.add(time.duration.hours(4));

        console.log("Setting event details:", {
            eventDate: eventDate.toString(),
            startTime: startTime.toString(),
            endTime: endTime.toString()
        });

        // Set event details with BN timestamps
        const tx1 = await parentContract.setEventDetails(
            "Test Event",
            "123 Main St",
            "Test Venue",
            eventDate,
            startTime,
            endTime,
            "Test Terms",
            { from: owner }
        );

        // Log debug state after setting event details
        const debugEvent1 = tx1.logs.find(log => log.event === 'DebugState');
        if (debugEvent1) {
            console.log("After setEventDetails:", {
                eventDate: debugEvent1.args.eventDate.toString(),
                totalRevenue: debugEvent1.args.totalRevenue.toString(),
                isActive: debugEvent1.args.isActive,
                owner: debugEvent1.args.owner,
                message: debugEvent1.args.message
            });
        }

        // Set ticketing details and verify owner
        await parentContract.setTicketingDetails(100, basePrice, false, { from: owner });

        // Mint a ticket with exact payment
        console.log("\nMinting ticket for:", attendee);
        console.log("Payment amount:", basePrice);

        const tx2 = await parentContract.mintTicket(attendee, { from: attendee, value: basePrice });
        console.log("Ticket minted successfully");

        // Get state after minting
        const summary = await parentContract.getEventSummary();
        console.log("Contract state after mint:", {
            eventDate: summary.eventDate.toString(),
            totalRevenue: summary.totalRevenue.toString(),
            currentPrice: summary.currentPrice.toString(),
            ticketSupply: summary.ticketSupply.toString()
        });
    });

    describe("Cancellation and Refunds", () => {
        it("should apply early cancellation penalty", async () => {
            // Verify ownership before cancellation
            const contractOwner = await parentContract.owner();
            console.log("\nPreparing for cancellation");
            console.log("Contract owner:", contractOwner);
            console.log("Transaction sender:", owner);
            assert.equal(contractOwner, owner, "Incorrect contract owner");

            // Get state before cancellation
            const summary = await parentContract.getEventSummary();
            console.log("State before cancellation:", {
                eventDate: summary.eventDate.toString(),
                totalRevenue: summary.totalRevenue.toString(),
                isActive: await parentContract.isEventActive()
            });

            try {
                console.log("Attempting to cancel event...");
                const tx = await parentContract.cancelEvent({ from: owner });
                console.log("Cancel transaction successful");

                // Log all events
                console.log("Transaction events:", tx.logs.map(log => log.event));

                const debugEvent = tx.logs.find(log => log.event === 'DebugState');
                if (debugEvent) {
                    console.log("During cancellation:", {
                        eventDate: debugEvent.args.eventDate.toString(),
                        totalRevenue: debugEvent.args.totalRevenue.toString(),
                        isActive: debugEvent.args.isActive,
                        owner: debugEvent.args.owner,
                        message: debugEvent.args.message
                    });
                }

                const penaltyEvent = tx.logs.find(log => log.event === 'CancellationPenalty');
                assert(penaltyEvent, "Penalty event not emitted");

                const totalRevenue = web3.utils.toBN(basePrice);
                const expectedPenalty = totalRevenue.mul(web3.utils.toBN(5)).div(web3.utils.toBN(100));

                assert.equal(
                    penaltyEvent.args.penaltyAmount.toString(),
                    expectedPenalty.toString(),
                    "Incorrect penalty amount"
                );
            } catch (error) {
                console.error("Cancel event failed:", error.message);
                throw error;
            }
        });
    });

    describe("Dynamic Pricing", () => {
        beforeEach(async () => {
            const latestTime = await time.latest();
            const eventDate = latestTime.add(time.duration.days(30));
            const startTime = eventDate.add(time.duration.hours(1));
            const endTime = startTime.add(time.duration.hours(4));

            await parentContract.setEventDetails(
                "Test Event",
                "123 Main St",
                "Test Venue",
                eventDate,
                startTime,
                endTime,
                "Test Terms",
                { from: owner }
            );

            await parentContract.setTicketingDetails(100, basePrice, true, { from: owner });
            await parentContract.setDynamicPricing(
                basePrice,
                maxPrice,
                minPrice,
                20, // 20% early bird discount
                Number(latestTime) + time.duration.days(7),
                150, // 150% demand multiplier
                { from: owner }
            );
        });

        it("should respect maximum price", async () => {
            // Advance time past early bird period
            await time.increase(time.duration.days(8));

            // Mint 95 tickets to maximize demand (95% sold)
            for(let i = 0; i < 95; i++) {
                const currentPrice = await parentContract.calculateCurrentPrice();
                await parentContract.mintTicket(attendee, { from: attendee, value: currentPrice });
            }

            const price = await parentContract.calculateCurrentPrice();
            assert.equal(price.toString(), maxPrice.toString(), "Should not exceed maximum price");
        });
    });
});