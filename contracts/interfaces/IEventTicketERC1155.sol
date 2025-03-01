// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IEventTicketERC1155 is IERC1155 {
    // Tier info struct
    struct TierInfo {
        uint256 price;
        uint256 maxSupply;
        uint256 currentSupply;
        string name;
        bool active;
    }

    // Events
    event TierCreated(uint256 indexed tierId, string name, uint256 price, uint256 maxSupply);
    event TicketsMinted(uint256 indexed tierId, address indexed to, uint256 amount);
    event TierStatusUpdated(uint256 indexed tierId, bool active);
    event RoyaltyPaid(uint256 indexed tierId, address indexed from, address indexed to, uint256 amount);

    // Core functionality
    function createTier(
        string memory name,
        uint256 price,
        uint256 maxSupply
    ) external returns (uint256);

    function mintTickets(
        address to,
        uint256 tierId,
        uint256 amount
    ) external;

    function setTierStatus(uint256 tierId, bool active) external;
    function getTierInfo(uint256 tierId) external view returns (TierInfo memory);
    function calculateRoyalty(uint256 tierId, uint256 salePrice) external view returns (uint256);
    function validateTierTransfer(
        address from,
        address to,
        uint256 tierId,
        uint256 amount
    ) external view returns (bool);
}
