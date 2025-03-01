// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IEventTicketERC721 is IERC721, IERC2981 {
    // Ticket info struct
    struct TicketInfo {
        uint256 price;
        uint256 eventId;
        uint256 seatNumber;
        bool resellable;
        address originalOwner;
    }

    // Events
    event TicketMinted(uint256 indexed ticketId, address indexed to, uint256 eventId);
    event ResaleStatusUpdated(uint256 indexed ticketId, bool resellable);
    event RoyaltyUpdated(uint256 newPercentage);

    // Core functionality
    function mintTicket(
        address to,
        uint256 eventId,
        uint256 seatNumber,
        uint256 price,
        bool resellable
    ) external returns (uint256);

    function setResaleStatus(uint256 ticketId, bool resellable) external;
    function setRoyaltyPercentage(uint256 percentage) external;
    function getTicketInfo(uint256 ticketId) external view returns (TicketInfo memory);
    function isResaleAllowed(uint256 ticketId) external view returns (bool);
    function validateTransfer(address from, address to, uint256 ticketId) external view returns (bool);
}
