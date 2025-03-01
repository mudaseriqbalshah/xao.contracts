// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interfaces/IEventTicketERC721.sol";
import "./XAOReputation.sol";

contract EventTicketERC721 is 
    ERC721,
    ERC2981,
    AccessControl,
    ReentrancyGuard
{
    using Counters for Counters.Counter;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint96 public constant MAX_ROYALTY_PERCENTAGE = 1000; // 10% max royalty
    uint96 public constant DEFAULT_ROYALTY_PERCENTAGE = 500; // 5% default royalty

    Counters.Counter private _tokenIdCounter;
    XAOReputation public xaoReputation;

    mapping(uint256 => IEventTicketERC721.TicketInfo) private _ticketInfo;
    mapping(uint256 => mapping(address => bool)) private _approvedResellers;

    // Events
    event TicketMinted(uint256 indexed ticketId, address indexed to, uint256 eventId);
    event ResaleStatusUpdated(uint256 indexed ticketId, bool resellable);
    event RoyaltyUpdated(uint96 newPercentage);

    constructor(address _xaoReputation) ERC721("XAO Event Ticket", "XAOTIX") {
        xaoReputation = XAOReputation(_xaoReputation);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);

        // Set default royalty to 5%
        _setDefaultRoyalty(msg.sender, DEFAULT_ROYALTY_PERCENTAGE);
    }

    function mintTicket(
        address to,
        uint256 eventId,
        uint256 seatNumber,
        uint256 price,
        bool resellable
    ) external onlyRole(MINTER_ROLE) returns (uint256) {
        require(to != address(0), "Invalid recipient");

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        _ticketInfo[tokenId] = IEventTicketERC721.TicketInfo({
            price: price,
            eventId: eventId,
            seatNumber: seatNumber,
            resellable: resellable,
            originalOwner: to
        });

        _safeMint(to, tokenId);

        emit TicketMinted(tokenId, to, eventId);
        return tokenId;
    }

    function setResaleStatus(uint256 ticketId, bool resellable) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_exists(ticketId), "Ticket does not exist");
        _ticketInfo[ticketId].resellable = resellable;
        emit ResaleStatusUpdated(ticketId, resellable);
    }

    function setRoyaltyPercentage(uint96 percentage) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(percentage <= MAX_ROYALTY_PERCENTAGE, "Royalty too high");
        _setDefaultRoyalty(msg.sender, percentage);
        emit RoyaltyUpdated(percentage);
    }

    function getTicketInfo(uint256 ticketId) 
        external 
        view 
        returns (IEventTicketERC721.TicketInfo memory) 
    {
        require(_exists(ticketId), "Ticket does not exist");
        return _ticketInfo[ticketId];
    }

    function isResaleAllowed(uint256 ticketId) 
        external 
        view 
        returns (bool) 
    {
        require(_exists(ticketId), "Ticket does not exist");
        return _ticketInfo[ticketId].resellable;
    }

    function validateTransfer(
        address from,
        address to,
        uint256 ticketId
    ) public view returns (bool) {
        if (from == address(0) || to == address(0)) return false;
        if (!_exists(ticketId)) return false;

        // Only check resale status (removed originalOwner exception)
        return _ticketInfo[ticketId].resellable;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);

        // Skip checks for minting
        if (from == address(0)) return;

        // Validate transfer for each token in batch
        for (uint256 i = 0; i < batchSize; i++) {
            uint256 tokenId = firstTokenId + i;
            require(
                validateTransfer(from, to, tokenId),
                "Transfer not allowed"
            );
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC2981, AccessControl)
        returns (bool)
    {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // Override royaltyInfo to ensure proper tuple return format
    function royaltyInfo(uint256 /*tokenId*/, uint256 salePrice) 
        public 
        view 
        virtual 
        override 
        returns (address receiver, uint256 royaltyAmount) 
    {
        (receiver, royaltyAmount) = super.royaltyInfo(0, salePrice);
        return (receiver, royaltyAmount);
    }
}