// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IEventExplorer {
    enum EventStatus { Upcoming, Ongoing, Completed, Canceled }
    enum ArtistStatus { Confirmed, Replaced, Canceled }

    event EventRegistered(address indexed eventContract);
    event EventStatusUpdated(address indexed eventContract, EventStatus status);
    event ArtistStatusUpdated(address indexed eventContract, address indexed artistContract, ArtistStatus status);
    event TicketAvailabilityUpdated(address indexed eventContract, uint256 remaining);
    event PriceUpdated(address indexed eventContract, uint256 newPrice);
    event RevenueUpdated(address indexed eventContract, address indexed artist, uint256 amount);

    function registerEvent(address _eventContract) external;
    function addAuthorizedViewer(address _eventContract, address _viewer) external;
    function updateEventStatus(address _eventContract, EventStatus _status) external;
    function updateArtistStatus(address _eventContract, address _artistContract, ArtistStatus _status) external;
    function updateArtistRevenue(address _eventContract, address _artist, uint256 _amount) external;
    function updateTicketAvailability(address _eventContract, uint256 _remaining) external;
    function updateCurrentPrice(address _eventContract, uint256 _newPrice) external;

    function getAllEvents() external view returns (address[] memory);
    function getEventDetails(address _eventContract) external view returns (
        EventStatus status,
        uint256 totalTickets,
        uint256 remainingTickets,
        uint256 currentPrice,
        address[] memory artists
    );
    function getPrivateEventData(address _eventContract, address _artist) external view returns (uint256);
    function getArtistStatus(address _eventContract, address _artistContract) external view returns (ArtistStatus);
    function isEventRegistered(address _eventContract) external view returns (bool);
    function isAuthorizedViewer(address _eventContract, address _viewer) external view returns (bool);
}