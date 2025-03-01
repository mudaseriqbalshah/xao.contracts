// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IParentEventContract.sol";
import "./interfaces/IArtistContract.sol";
import "./libraries/EventDataTypes.sol";

/// @title Parent Event Contract
/// @author XAO Protocol Team
/// @notice This contract manages event creation, ticketing, and artist relationships
/// @dev Implements ERC721 for NFT tickets, includes dynamic pricing and cancellation logic
contract ParentEventContract is IParentEventContract, ERC721, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using EventDataTypes for EventDataTypes.EventDetails;

    /// @notice Storage for event details and pricing
    EventDataTypes.EventDetails private eventDetails;
    /// @notice Mapping of linked artist contract addresses
    mapping(address => bool) public linkedArtists;
    /// @notice Counter for NFT token IDs
    uint256 private _tokenIdCounter;
    /// @notice Flag indicating if the event is currently active
    bool public isEventActive;
    /// @notice Address of the allowed artist factory contract
    address public immutable allowedArtistFactory;

    /// @notice Mapping to track the purchase price of each ticket
    mapping(uint256 => uint256) private purchasePrices;

    /// @notice Early cancellation window duration
    uint256 public constant EARLY_CANCEL_WINDOW = 30 days;
    /// @notice Late cancellation window duration
    uint256 public constant LATE_CANCEL_WINDOW = 7 days;
    /// @notice Early cancellation penalty percentage (5%)
    uint256 public constant EARLY_CANCEL_PENALTY = 5;
    /// @notice Late cancellation penalty percentage (15%)
    uint256 public constant LATE_CANCEL_PENALTY = 15;
    /// @notice Very late cancellation penalty percentage (30%)
    uint256 public constant VERY_LATE_CANCEL_PENALTY = 30;

    /// @notice Emitted when a cancellation penalty is applied
    event CancellationPenalty(uint256 penaltyAmount, uint256 penaltyPercentage);
    /// @notice Emitted for debugging state changes
    event DebugState(uint256 eventDate, uint256 totalRevenue, bool isActive, address owner, string message);

    /// @notice Initializes a new event contract
    /// @dev Sets up the ERC721 token and links to the artist factory
    /// @param _allowedArtistFactory Address of the authorized artist factory contract
    constructor(address _allowedArtistFactory) ERC721("Event Ticket", "TCKT") {
        require(_allowedArtistFactory != address(0), "Invalid factory address");
        allowedArtistFactory = _allowedArtistFactory;
        isEventActive = true;
        _transferOwnership(msg.sender);
        emit DebugState(0, 0, true, msg.sender, "Contract initialized");
    }

    /// @notice Ensures the event is active for operations
    modifier onlyActive() {
        require(isEventActive, "Event is not active");
        _;
    }

    /// @notice Sets up the main event details
    /// @dev Must be called by the contract owner
    /// @param _eventName Name of the event
    /// @param _eventAddress Physical location of the event
    /// @param _venueName Name of the venue
    /// @param _eventDate Date of the event
    /// @param _eventStartTime Start time of the event
    /// @param _eventEndTime End time of the event
    /// @param _legalText Legal terms and conditions
    function setEventDetails(
        string memory _eventName,
        string memory _eventAddress,
        string memory _venueName,
        uint256 _eventDate,
        uint256 _eventStartTime,
        uint256 _eventEndTime,
        string memory _legalText
    ) external override onlyOwner {
        require(bytes(_eventName).length > 0, "Event name cannot be empty");
        require(bytes(_eventAddress).length > 0, "Event address cannot be empty");
        require(bytes(_venueName).length > 0, "Venue name cannot be empty");
        require(_eventDate > block.timestamp, "Invalid event date");
        require(_eventStartTime > _eventDate, "Start time must be after event date");
        require(_eventEndTime > _eventStartTime, "End time must be after start time");

        eventDetails.eventName = _eventName;
        eventDetails.eventAddress = _eventAddress;
        eventDetails.venueName = _venueName;
        eventDetails.eventDate = _eventDate;
        eventDetails.eventStartTime = _eventStartTime;
        eventDetails.eventEndTime = _eventEndTime;
        eventDetails.legalText = _legalText;
        eventDetails.isCancelled = false;

        emit EventDetailsSet(_eventName, _eventDate);
        emit DebugState(_eventDate, eventDetails.totalRevenue, isEventActive, owner(), "Event details set");
    }

    /// @notice Sets the ticketing details for the event
    /// @dev Only callable by the contract owner
    /// @param _ticketSupply Total number of tickets available
    /// @param _ticketPrice Initial price of each ticket
    /// @param _dynamicPricingEnabled Flag to enable/disable dynamic pricing
    function setTicketingDetails(
        uint256 _ticketSupply,
        uint256 _ticketPrice,
        bool _dynamicPricingEnabled
    ) external override onlyOwner {
        require(_ticketSupply > 0, "Invalid ticket supply");
        require(_ticketPrice > 0, "Invalid ticket price");

        eventDetails.ticketSupply = _ticketSupply;
        eventDetails.ticketPrice = _ticketPrice;
        eventDetails.dynamicPricingEnabled = _dynamicPricingEnabled;

        emit DebugState(eventDetails.eventDate, eventDetails.totalRevenue, isEventActive, owner(), "Ticketing details set");
    }

    /// @notice Calculates the cancellation penalty based on the time remaining until the event
    /// @dev Internal function used in `cancelEvent`
    /// @return The cancellation penalty percentage
    function calculateCancellationPenalty() internal view returns (uint256) {
        require(eventDetails.eventDate > 0, "Event date not set [calculatePenalty]");
        require(block.timestamp < eventDetails.eventDate, "Event already occurred [calculatePenalty]");
        require(eventDetails.totalRevenue > 0, "No revenue to calculate penalty [calculatePenalty]");

        uint256 timeToEvent = eventDetails.eventDate.sub(block.timestamp);

        if (timeToEvent >= EARLY_CANCEL_WINDOW) {
            return EARLY_CANCEL_PENALTY;
        } else if (timeToEvent >= LATE_CANCEL_WINDOW) {
            return LATE_CANCEL_PENALTY;
        } else {
            return VERY_LATE_CANCEL_PENALTY;
        }
    }

    /// @notice Cancels the event and applies a cancellation penalty
    /// @dev Only callable by the contract owner
    function cancelEvent() external override onlyOwner {
        emit DebugState(eventDetails.eventDate, eventDetails.totalRevenue, isEventActive, owner(), "Pre-cancel check");

        require(!eventDetails.isCancelled, "Already cancelled");
        require(owner() == msg.sender, "Only contract owner can cancel [owner check]");
        require(eventDetails.eventDate > 0, "Event date not set [cancelEvent]");
        require(block.timestamp < eventDetails.eventDate, "Event already occurred [cancelEvent]");
        require(eventDetails.totalRevenue > 0, "No revenue to calculate penalty [cancelEvent]");

        uint256 penaltyPercentage = calculateCancellationPenalty();
        uint256 penaltyAmount = eventDetails.totalRevenue.mul(penaltyPercentage).div(100);

        isEventActive = false;
        eventDetails.isCancelled = true;

        emit EventCancelled();
        emit CancellationPenalty(penaltyAmount, penaltyPercentage);
        emit DebugState(eventDetails.eventDate, eventDetails.totalRevenue, isEventActive, owner(), "Event cancelled");
    }

    /// @notice Mints a ticket for the event
    /// @dev Only callable while the event is active
    /// @param to The address to mint the ticket to
    /// @return The ID of the minted ticket
    function mintTicket(address to) external payable override onlyActive returns (uint256) {
        require(_tokenIdCounter < eventDetails.ticketSupply, "All tickets minted");
        require(to != address(0), "Invalid address");
        require(eventDetails.ticketPrice > 0, "Ticket price not set");
        require(msg.value >= calculateCurrentPrice(), "Insufficient payment");

        uint256 tokenId = _tokenIdCounter;
        uint256 price = calculateCurrentPrice();

        _safeMint(to, tokenId);
        _tokenIdCounter = _tokenIdCounter.add(1);

        eventDetails.totalRevenue = eventDetails.totalRevenue.add(price);
        purchasePrices[tokenId] = price;

        emit DebugState(eventDetails.eventDate, eventDetails.totalRevenue, isEventActive, owner(), "Ticket minted");

        // Refund excess payment if any
        if (msg.value > price) {
            (bool success, ) = msg.sender.call{value: msg.value.sub(price)}("");
            require(success, "Refund failed");
        }

        emit TicketMinted(to, tokenId);
        emit PriceUpdated(price);

        return tokenId;
    }

    /// @notice Calculates the current price of a ticket based on dynamic pricing rules
    /// @dev Takes into account early bird discounts and demand-based pricing
    /// @return The current price of a ticket
    function calculateCurrentPrice() public view override returns (uint256) {
        if (!eventDetails.dynamicPricingEnabled) {
            return eventDetails.ticketPrice;
        }

        uint256 soldPercentage = _tokenIdCounter.mul(100).div(eventDetails.ticketSupply);
        EventDataTypes.DynamicPricing storage pricing = eventDetails.dynamicPricing;
        uint256 currentPrice = pricing.basePrice;

        // Early bird discount
        if (block.timestamp < pricing.earlyBirdEndTime) {
            uint256 discount = currentPrice.mul(pricing.earlyBirdDiscount).div(100);
            currentPrice = currentPrice.sub(discount);
        }

        // High demand direct max price
        if (soldPercentage >= 95) {
            return pricing.maxPrice;
        }

        // Demand-based pricing
        if (_tokenIdCounter > eventDetails.ticketSupply.div(2)) {
            uint256 demandFactor = soldPercentage.sub(50); // Calculate percentage above 50%
            uint256 priceIncrease = pricing.basePrice.mul(pricing.demandMultiplier).mul(demandFactor).div(10000);
            currentPrice = currentPrice.add(priceIncrease);
        }

        // Enforce price bounds
        if (currentPrice > pricing.maxPrice) {
            currentPrice = pricing.maxPrice;
        }
        if (currentPrice < pricing.minPrice) {
            currentPrice = pricing.minPrice;
        }

        return currentPrice;
    }

    /// @notice Configures dynamic pricing parameters
    /// @dev Only callable by the contract owner
    /// @param _basePrice Base price of a ticket
    /// @param _maxPrice Maximum price of a ticket
    /// @param _minPrice Minimum price of a ticket
    /// @param _earlyBirdDiscount Percentage discount for early bird tickets
    /// @param _earlyBirdEndTime Timestamp marking the end of the early bird period
    /// @param _demandMultiplier Multiplier for demand-based pricing
    function setDynamicPricing(
        uint256 _basePrice,
        uint256 _maxPrice,
        uint256 _minPrice,
        uint256 _earlyBirdDiscount,
        uint256 _earlyBirdEndTime,
        uint256 _demandMultiplier
    ) external override onlyOwner {
        require(_maxPrice > _basePrice && _basePrice > _minPrice, "Invalid price range");
        require(_earlyBirdDiscount <= 50, "Max discount is 50%");
        require(_demandMultiplier <= 200, "Max multiplier is 200%");

        EventDataTypes.DynamicPricing storage pricing = eventDetails.dynamicPricing;
        pricing.basePrice = _basePrice;
        pricing.maxPrice = _maxPrice;
        pricing.minPrice = _minPrice;
        pricing.earlyBirdDiscount = _earlyBirdDiscount;
        pricing.earlyBirdEndTime = _earlyBirdEndTime;
        pricing.demandMultiplier = _demandMultiplier;

        eventDetails.dynamicPricingEnabled = true;
        emit DynamicPricingConfigured(_basePrice, _maxPrice, _minPrice);
    }

    /// @notice Adds a new pricing tier to the event
    /// @dev Only callable by the contract owner
    /// @param maxTickets Maximum number of tickets in this tier
    /// @param price Price of tickets in this tier
    function addPricingTier(uint256 maxTickets, uint256 price) external override onlyOwner {
        require(maxTickets > 0, "Invalid ticket count");
        require(price > 0, "Invalid price");

        uint256 tierId = eventDetails.tierCount;
        eventDetails.tierCount = eventDetails.tierCount.add(1);

        EventDataTypes.PricingTier storage tier = eventDetails.pricingTiers[tierId];
        tier.maxTickets = maxTickets;
        tier.price = price;
        tier.active = true;

        emit TierAdded(tierId, maxTickets, price);
    }

    /// @notice Links an artist contract to the event
    /// @dev Allows associating artists with the event
    /// @param artistContract Address of the artist contract
    function linkArtistContract(address artistContract) external override {
        require(artistContract != address(0), "Invalid artist contract");
        require(!linkedArtists[artistContract], "Artist already linked");
        linkedArtists[artistContract] = true;
        emit ArtistContractLinked(artistContract);
    }

    /// @notice Checks if an artist contract is linked to the event
    /// @param artistContract Address of the artist contract
    /// @return True if the artist contract is linked, false otherwise
    function isArtistLinked(address artistContract) external view override returns (bool) {
        return linkedArtists[artistContract];
    }

    /// @notice Deposits funds into the event's escrow balance
    /// @dev Only callable by the contract owner
    function depositGuarantee() external override payable onlyOwner {
        eventDetails.escrowBalance = eventDetails.escrowBalance.add(msg.value);
    }

    /// @notice Processes a payment from the escrow balance
    /// @dev Only callable by the contract owner, prevents reentrancy attacks
    /// @param recipient Address to send the payment to
    /// @param amount Amount to send
    function processPayment(address payable recipient, uint256 amount)
        external
        override
        onlyOwner
        nonReentrant
    {
        require(amount <= eventDetails.escrowBalance, "Insufficient escrow balance");
        eventDetails.escrowBalance = eventDetails.escrowBalance.sub(amount);
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Payment failed");
        emit PaymentProcessed(recipient, amount);
    }

    /// @notice Retrieves a summary of the event details
    /// @return eventName Name of the event
    /// @return eventAddress Address of the event
    /// @return venueName Name of the venue
    /// @return eventDate Date of the event
    /// @return eventStartTime Start time of the event
    /// @return eventEndTime End time of the event
    /// @return legalText Legal text of the event
    /// @return ticketSupply Total ticket supply
    /// @return currentPrice Current price of a ticket
    /// @return dynamicPricingEnabled True if dynamic pricing is enabled, false otherwise
    /// @return totalRevenue Total revenue generated
    function getEventSummary() external view override returns (
        string memory eventName,
        string memory eventAddress,
        string memory venueName,
        uint256 eventDate,
        uint256 eventStartTime,
        uint256 eventEndTime,
        string memory legalText,
        uint256 ticketSupply,
        uint256 currentPrice,
        bool dynamicPricingEnabled,
        uint256 totalRevenue
    ) {
        return (
            eventDetails.eventName,
            eventDetails.eventAddress,
            eventDetails.venueName,
            eventDetails.eventDate,
            eventDetails.eventStartTime,
            eventDetails.eventEndTime,
            eventDetails.legalText,
            eventDetails.ticketSupply,
            calculateCurrentPrice(),
            eventDetails.dynamicPricingEnabled,
            eventDetails.totalRevenue
        );
    }

    /// @notice Retrieves the ticketing details of the event
    /// @return supply Total ticket supply
    /// @return price Current ticket price
    /// @return dynamicEnabled True if dynamic pricing is enabled, false otherwise
    function getTicketingDetails() external view override returns (
        uint256 supply,
        uint256 price,
        bool dynamicEnabled
    ) {
        return (
            eventDetails.ticketSupply,
            calculateCurrentPrice(),
            eventDetails.dynamicPricingEnabled
        );
    }

    /// @notice Retrieves the purchase price of a specific token ID
    /// @param tokenId The token ID to check
    /// @return The purchase price of the token
    function getPurchasePrice(uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), "Token does not exist");
        return purchasePrices[tokenId];
    }

    /// @notice Hook that's called before each transfer
    /// @dev Checks if event is active before transferring tokens, except for burns
    /// @param from Sender of the token
    /// @param to Receiver of the token
    /// @param tokenId Token ID being transferred
    /// @param batchSize Batch size being transferred
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        // Allow burns (transfers to zero address) even when event is not active
        if (to != address(0)) {
            require(isEventActive, "Event is not active");
        }
    }
}