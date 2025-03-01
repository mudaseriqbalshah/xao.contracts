// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library EventDataTypes {
    struct PricingTier {
        uint256 maxTickets;
        uint256 price;
        bool active;
    }

    struct DynamicPricing {
        uint256 basePrice;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 earlyBirdDiscount;
        uint256 earlyBirdEndTime;
        uint256 demandMultiplier;
    }

    struct EventDetails {
        string eventName;
        string eventAddress;
        string venueName;
        uint256 eventDate;
        uint256 eventStartTime;
        uint256 eventEndTime;
        string legalText;
        uint256 ticketSupply;
        uint256 ticketPrice;
        bool dynamicPricingEnabled;
        uint256 totalRevenue;
        uint256 escrowBalance;
        mapping(uint256 => PricingTier) pricingTiers;
        uint256 tierCount;
        DynamicPricing dynamicPricing;
        bool isCancelled;
        uint256 cancellationTime;
        uint256 refundDeadline;
    }
}
