// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interfaces/IEventTicketERC1155.sol";
import "./XAOReputation.sol";

contract EventTicketERC1155 is 
    ERC1155,
    AccessControl,
    ReentrancyGuard,
    IEventTicketERC1155
{
    using Counters for Counters.Counter;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant ROYALTY_PERCENTAGE = 500; // 5% royalty

    Counters.Counter private _tierIdCounter;
    XAOReputation public xaoReputation;

    mapping(uint256 => TierInfo) private _tierInfo;
    mapping(uint256 => mapping(address => bool)) private _approvedResellers;
    mapping(uint256 => address) private _tierCreators;

    constructor(
        string memory uri,
        address _xaoReputation
    ) ERC1155(uri) {
        xaoReputation = XAOReputation(_xaoReputation);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
    }

    function createTier(
        string memory name,
        uint256 price,
        uint256 maxSupply
    ) external override onlyRole(MINTER_ROLE) returns (uint256) {
        require(bytes(name).length > 0, "Empty name");
        require(price > 0, "Invalid price");
        require(maxSupply > 0, "Invalid supply");

        uint256 tierId = _tierIdCounter.current();
        _tierIdCounter.increment();

        _tierInfo[tierId] = TierInfo({
            price: price,
            maxSupply: maxSupply,
            currentSupply: 0,
            name: name,
            active: true
        });

        _tierCreators[tierId] = msg.sender;

        emit TierCreated(tierId, name, price, maxSupply);
        return tierId;
    }

    function mintTickets(
        address to,
        uint256 tierId,
        uint256 amount
    ) external override onlyRole(MINTER_ROLE) nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(_tierInfo[tierId].active, "Tier not active");
        require(
            _tierInfo[tierId].currentSupply + amount <= _tierInfo[tierId].maxSupply,
            "Exceeds max supply"
        );

        _tierInfo[tierId].currentSupply += amount;
        _mint(to, tierId, amount, "");

        emit TicketsMinted(tierId, to, amount);
    }

    function setTierStatus(uint256 tierId, bool active) 
        external 
        override 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_tierInfo[tierId].maxSupply > 0, "Tier does not exist");
        _tierInfo[tierId].active = active;
        emit TierStatusUpdated(tierId, active);
    }

    function getTierInfo(uint256 tierId) 
        external 
        view 
        override 
        returns (TierInfo memory) 
    {
        require(_tierInfo[tierId].maxSupply > 0, "Tier does not exist");
        return _tierInfo[tierId];
    }

    function calculateRoyalty(uint256 tierId, uint256 salePrice) 
        external 
        view 
        override 
        returns (uint256) 
    {
        require(_tierInfo[tierId].maxSupply > 0, "Tier does not exist");
        return (salePrice * ROYALTY_PERCENTAGE) / 10000;
    }

    // Internal function for transfer validation
    function _validateTierTransfer(
        address from,
        address to,
        uint256 tierId,
        uint256 amount
    ) internal view returns (bool) {
        if (from == address(0) || to == address(0)) return false;
        if (_tierInfo[tierId].maxSupply == 0) return false;

        // Allow original minting and approved transfers
        if (from == _tierCreators[tierId]) return true;
        if (_approvedResellers[tierId][from]) return true;

        // Check if tier is active
        return _tierInfo[tierId].active;
    }

    // Public wrapper for external validation
    function validateTierTransfer(
        address from,
        address to,
        uint256 tierId,
        uint256 amount
    ) external view override returns (bool) {
        return _validateTierTransfer(from, to, tierId, amount);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        // Skip checks for minting
        if (from == address(0)) return;

        for (uint256 i = 0; i < ids.length; i++) {
            require(
                _validateTierTransfer(from, to, ids[i], amounts[i]),
                "Transfer not allowed"
            );

            // Handle royalty payment on transfer
            if (from != _tierCreators[ids[i]]) {
                uint256 royalty = (amounts[i] * _tierInfo[ids[i]].price * ROYALTY_PERCENTAGE) / 10000;
                emit RoyaltyPaid(ids[i], from, _tierCreators[ids[i]], royalty);
            }
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, AccessControl, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IEventTicketERC1155).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}