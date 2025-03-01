// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IParentEventContract.sol";
import "./interfaces/IArtistContract.sol";

/// @title Event Explorer Contract
/// @author XAO Protocol Team
/// @notice This contract provides a central registry and explorer for all events in the platform
/// @dev Implements event registration, status tracking, and artist management functionality
contract EventExplorer is Ownable {
    enum EventStatus { Upcoming, Ongoing, Completed, Canceled }
    enum ArtistStatus { Confirmed, Replaced, Canceled }

    /// @notice Structure containing comprehensive event information
    /// @dev Includes event details, artist information, and ticket data
    struct EventInfo {
        address eventContract;
        EventStatus status;
        address[] artistContracts;
        mapping(address => ArtistStatus) artistStatus;
        uint256 totalTickets;
        uint256 remainingTickets;
        uint256 currentPrice;
        mapping(address => uint256) artistRevenue;  // Private revenue data
        mapping(address => bool) authorizedViewers;  // Wallet-based access control
    }

    /// @notice Array of all registered event contracts
    address[] public eventContracts;
    /// @notice Mapping of event contract addresses to their detailed information
    mapping(address => EventInfo) public eventInfo;
    /// @notice Mapping to track artist ticket sales
    mapping(address => mapping(address => bool)) private artistTicketSales;

    /// @notice Emitted when a new event is registered
    event EventRegistered(address indexed eventContract);
    /// @notice Emitted when an event's status is updated
    event EventStatusUpdated(address indexed eventContract, EventStatus status);
    /// @notice Emitted when an artist's status is updated
    event ArtistStatusUpdated(address indexed eventContract, address indexed artistContract, ArtistStatus status);
    /// @notice Emitted when ticket availability changes
    event TicketAvailabilityUpdated(address indexed eventContract, uint256 remaining);
    /// @notice Emitted when ticket price is updated
    event PriceUpdated(address indexed eventContract, uint256 newPrice);
    /// @notice Emitted when artist revenue is updated
    event RevenueUpdated(address indexed eventContract, address indexed artist, uint256 amount);

    /// @notice Restricts access to authorized users only
    /// @param _eventContract The event contract address to check authorization for
    modifier onlyAuthorized(address _eventContract) {
        require(
            msg.sender == owner() || 
            eventInfo[_eventContract].authorizedViewers[msg.sender],
            "Not authorized"
        );
        _;
    }

    /// @notice Registers a new event in the explorer
    /// @param _eventContract Address of the event contract to register
    function registerEvent(address _eventContract) external {
        require(_eventContract != address(0), "Invalid event contract");
        require(!isEventRegistered(_eventContract), "Event already registered");

        eventContracts.push(_eventContract);
        EventInfo storage newEvent = eventInfo[_eventContract];
        newEvent.eventContract = _eventContract;
        newEvent.status = EventStatus.Upcoming;

        IParentEventContract event_ = IParentEventContract(_eventContract);
        (uint256 supply, uint256 price,) = event_.getTicketingDetails();
        newEvent.totalTickets = supply;
        newEvent.remainingTickets = supply;
        newEvent.currentPrice = price;

        // Set event creator as authorized viewer
        newEvent.authorizedViewers[msg.sender] = true;

        emit EventRegistered(_eventContract);
    }

    /// @notice Adds an authorized viewer for an event
    /// @param _eventContract Address of the event contract
    /// @param _viewer Address to be authorized
    function addAuthorizedViewer(address _eventContract, address _viewer) 
        external 
        onlyAuthorized(_eventContract) 
    {
        eventInfo[_eventContract].authorizedViewers[_viewer] = true;
    }

    /// @notice Updates the status of an event
    /// @param _eventContract Address of the event contract
    /// @param _status New status to set
    function updateEventStatus(address _eventContract, EventStatus _status) 
        external 
        onlyOwner 
    {
        require(isEventRegistered(_eventContract), "Event not registered");
        eventInfo[_eventContract].status = _status;
        emit EventStatusUpdated(_eventContract, _status);
    }

    /// @notice Updates the status of an artist for an event
    /// @param _eventContract Address of the event contract
    /// @param _artistContract Address of the artist contract
    /// @param _status New status to set
    function updateArtistStatus(
        address _eventContract,
        address _artistContract,
        ArtistStatus _status
    ) external onlyOwner {
        require(isEventRegistered(_eventContract), "Event not registered");
        eventInfo[_eventContract].artistStatus[_artistContract] = _status;
        emit ArtistStatusUpdated(_eventContract, _artistContract, _status);
    }

    /// @notice Updates an artist's revenue for an event
    /// @param _eventContract Address of the event contract
    /// @param _artist Address of the artist
    /// @param _amount New revenue amount
    function updateArtistRevenue(
        address _eventContract,
        address _artist,
        uint256 _amount
    ) external onlyOwner {
        require(isEventRegistered(_eventContract), "Event not registered");
        eventInfo[_eventContract].artistRevenue[_artist] = _amount;
        emit RevenueUpdated(_eventContract, _artist, _amount);
    }

    /// @notice Updates ticket availability for an event
    /// @param _eventContract Address of the event contract
    /// @param _remaining Number of remaining tickets
    function updateTicketAvailability(
        address _eventContract,
        uint256 _remaining
    ) external onlyOwner {
        require(isEventRegistered(_eventContract), "Event not registered");
        eventInfo[_eventContract].remainingTickets = _remaining;
        emit TicketAvailabilityUpdated(_eventContract, _remaining);
    }

    /// @notice Updates current ticket price for an event
    /// @param _eventContract Address of the event contract
    /// @param _newPrice New ticket price
    function updateCurrentPrice(
        address _eventContract,
        uint256 _newPrice
    ) external onlyOwner {
        require(isEventRegistered(_eventContract), "Event not registered");
        eventInfo[_eventContract].currentPrice = _newPrice;
        emit PriceUpdated(_eventContract, _newPrice);
    }

    /// @notice Gets all registered events
    /// @return Array of event contract addresses
    function getAllEvents() external view returns (address[] memory) {
        return eventContracts;
    }

    /// @notice Gets detailed information about an event
    /// @param _eventContract Address of the event contract
    /// @return status Current status of the event
    /// @return totalTickets Total number of tickets
    /// @return remainingTickets Number of remaining tickets
    /// @return currentPrice Current ticket price
    /// @return artists Array of artist contract addresses
    function getEventDetails(address _eventContract) external view returns (
        EventStatus status,
        uint256 totalTickets,
        uint256 remainingTickets,
        uint256 currentPrice,
        address[] memory artists
    ) {
        require(isEventRegistered(_eventContract), "Event not registered");
        EventInfo storage event_ = eventInfo[_eventContract];
        return (
            event_.status,
            event_.totalTickets,
            event_.remainingTickets,
            event_.currentPrice,
            event_.artistContracts
        );
    }

    /// @notice Gets private event data for authorized viewers
    /// @param _eventContract Address of the event contract
    /// @param _artist Address of the artist
    /// @return Artist's revenue for the event
    function getPrivateEventData(address _eventContract, address _artist) 
        external 
        view 
        onlyAuthorized(_eventContract) 
        returns (uint256) 
    {
        require(isEventRegistered(_eventContract), "Event not registered");
        return eventInfo[_eventContract].artistRevenue[_artist];
    }

    /// @notice Gets the status of an artist for an event
    /// @param _eventContract Address of the event contract
    /// @param _artistContract Address of the artist contract
    /// @return Status of the artist
    function getArtistStatus(address _eventContract, address _artistContract)
        external
        view
        returns (ArtistStatus)
    {
        require(isEventRegistered(_eventContract), "Event not registered");
        return eventInfo[_eventContract].artistStatus[_artistContract];
    }

    /// @notice Checks if an event is registered
    /// @param _eventContract Address of the event contract to check
    /// @return True if the event is registered
    function isEventRegistered(address _eventContract) public view returns (bool) {
        return eventInfo[_eventContract].eventContract == _eventContract;
    }

    /// @notice Checks if an address is an authorized viewer for an event
    /// @param _eventContract Address of the event contract
    /// @param _viewer Address to check
    /// @return True if the address is an authorized viewer
    function isAuthorizedViewer(address _eventContract, address _viewer) 
        external 
        view 
        returns (bool) 
    {
        return eventInfo[_eventContract].authorizedViewers[_viewer];
    }
}