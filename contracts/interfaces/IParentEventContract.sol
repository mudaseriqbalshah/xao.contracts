// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/EventDataTypes.sol";

/// @title Parent Event Contract Interface
/// @author XAO Protocol Team
/// @notice Interface defining core event management functionality
/// @dev Implements event creation, ticketing, and artist management functions
interface IParentEventContract {
    /// @notice Emitted when event details are set
    event EventDetailsSet(string eventName, uint256 eventDate);
    /// @notice Emitted when a new ticket is minted
    event TicketMinted(address to, uint256 tokenId);
    /// @notice Emitted when an artist contract is linked
    event ArtistContractLinked(address artistContract);
    /// @notice Emitted when an artist is replaced
    event ArtistReplaced(address oldArtist, address newArtist);
    /// @notice Emitted when an event is cancelled
    event EventCancelled();
    /// @notice Emitted when a payment is processed
    event PaymentProcessed(address recipient, uint256 amount);
    /// @notice Emitted when ticket price is updated
    event PriceUpdated(uint256 newPrice);
    /// @notice Emitted when a new pricing tier is added
    event TierAdded(uint256 tierId, uint256 maxTickets, uint256 price);
    /// @notice Emitted when dynamic pricing is configured
    event DynamicPricingConfigured(uint256 basePrice, uint256 maxPrice, uint256 minPrice);

    /// @notice Sets the main event details
    /// @param _eventName Name of the event
    /// @param _eventAddress Physical location
    /// @param _venueName Venue name
    /// @param _eventDate Event date
    /// @param _eventStartTime Start time
    /// @param _eventEndTime End time
    /// @param _legalText Legal terms
    function setEventDetails(
        string memory _eventName,
        string memory _eventAddress,
        string memory _venueName,
        uint256 _eventDate,
        uint256 _eventStartTime,
        uint256 _eventEndTime,
        string memory _legalText
    ) external;

    /// @notice Sets ticketing parameters
    /// @param _ticketSupply Total number of tickets
    /// @param _ticketPrice Base ticket price
    /// @param _dynamicPricingEnabled Enable dynamic pricing
    function setTicketingDetails(
        uint256 _ticketSupply,
        uint256 _ticketPrice,
        bool _dynamicPricingEnabled
    ) external;

    /// @notice Configures dynamic pricing parameters
    /// @param _basePrice Base ticket price
    /// @param _maxPrice Maximum allowed price
    /// @param _minPrice Minimum allowed price
    /// @param _earlyBirdDiscount Early bird discount percentage
    /// @param _earlyBirdEndTime End time for early bird pricing
    /// @param _demandMultiplier Multiplier for demand-based pricing
    function setDynamicPricing(
        uint256 _basePrice,
        uint256 _maxPrice,
        uint256 _minPrice,
        uint256 _earlyBirdDiscount,
        uint256 _earlyBirdEndTime,
        uint256 _demandMultiplier
    ) external;

    /// @notice Adds a new pricing tier
    /// @param maxTickets Maximum tickets in this tier
    /// @param price Price for this tier
    function addPricingTier(uint256 maxTickets, uint256 price) external;

    /// @notice Calculates current ticket price
    /// @return Current ticket price based on demand and timing
    function calculateCurrentPrice() external view returns (uint256);

    /// @notice Mints a new ticket NFT
    /// @param to Address to mint the ticket to
    /// @return Token ID of the minted ticket
    function mintTicket(address to) external payable returns (uint256);

    /// @notice Links an artist contract to the event
    /// @param artistContract Address of the artist contract
    function linkArtistContract(address artistContract) external;

    /// @notice Deposits guarantee amount for artist payment
    function depositGuarantee() external payable;

    /// @notice Processes payment to a recipient
    /// @param recipient Address to receive payment
    /// @param amount Amount to pay
    function processPayment(address payable recipient, uint256 amount) external;

    /// @notice Cancels the event
    function cancelEvent() external;

    /// @notice Checks if an artist contract is linked
    /// @param artistContract Address of the artist contract
    /// @return True if the artist is linked
    function isArtistLinked(address artistContract) external view returns (bool);

    /// @notice Gets comprehensive event information
    /// @return eventName Name of the event
    /// @return eventAddress Physical location
    /// @return venueName Venue name
    /// @return eventDate Event date
    /// @return eventStartTime Start time
    /// @return eventEndTime End time
    /// @return legalText Legal terms
    /// @return ticketSupply Total ticket supply
    /// @return currentPrice Current ticket price
    /// @return dynamicPricingEnabled Dynamic pricing status
    /// @return totalRevenue Total revenue generated
    function getEventSummary() external view returns (
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
    );

    /// @notice Gets ticketing configuration
    /// @return supply Total ticket supply
    /// @return price Current ticket price
    /// @return dynamicEnabled Dynamic pricing status
    function getTicketingDetails() external view returns (
        uint256 supply,
        uint256 price,
        bool dynamicEnabled
    );
}