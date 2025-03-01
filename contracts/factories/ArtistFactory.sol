// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../ArtistContract.sol";
import "./EventFactory.sol";
import "../ParentEventContract.sol";

/// @title Artist Factory Contract
/// @author XAO Protocol Team
/// @notice This contract manages the creation and tracking of artist contracts
/// @dev Implements factory pattern for creating new artist contracts with proper linkage to events
contract ArtistFactory is Ownable {
    /// @notice Reference to the event factory contract
    EventFactory public eventFactory;

    /// @notice Array to track all created artist contracts
    address[] public artists;

    /// @notice Mapping to check if an address is a created artist contract
    mapping(address => bool) public isArtist;

    /// @notice Mapping to track artist contracts per event
    mapping(address => address[]) public eventToArtists;

    /// @notice Emitted when a new artist contract is created
    /// @param artistContract Address of the new artist contract
    /// @param artist Address of the artist
    /// @param eventContract Address of the associated event contract
    event ArtistCreated(address indexed artistContract, address indexed artist, address indexed eventContract);
    
    /// @notice Emitted when the event factory address is set
    /// @param eventFactory Address of the event factory contract
    event EventFactorySet(address eventFactory);

    /// @notice Sets the event factory contract address
    /// @dev Can only be called by the contract owner
    /// @param _eventFactory Address of the event factory contract
    function setEventFactory(address _eventFactory) external onlyOwner {
        require(_eventFactory != address(0), "Invalid event factory");
        eventFactory = EventFactory(_eventFactory);
        emit EventFactorySet(_eventFactory);
    }

    /// @notice Creates a new artist contract for an event
    /// @dev Links the artist contract with the event and transfers ownership
    /// @param _eventContract Address of the event contract
    /// @param _artist Address of the artist
    /// @return Address of the newly created artist contract
    function createArtistContract(address _eventContract, address _artist) 
        external 
        returns (address) 
    {
        require(address(eventFactory) != address(0), "Event factory not set");
        require(eventFactory.isEvent(_eventContract), "Invalid event contract");

        // Deploy new artist contract
        ArtistContract newArtist = new ArtistContract(_eventContract, _artist);

        // Record the new artist contract
        artists.push(address(newArtist));
        isArtist[address(newArtist)] = true;
        eventToArtists[_eventContract].push(address(newArtist));

        // Transfer ownership of artist contract to the event contract
        newArtist.transferOwnership(_eventContract);

        // Link artist contract with event
        ParentEventContract(_eventContract).linkArtistContract(address(newArtist));

        emit ArtistCreated(address(newArtist), _artist, _eventContract);

        return address(newArtist);
    }

    /// @notice Gets the total number of artist contracts created
    /// @return Total count of artist contracts
    function getArtistCount() external view returns (uint256) {
        return artists.length;
    }

    /// @notice Gets all artist contracts associated with an event
    /// @param _eventContract Address of the event contract
    /// @return Array of artist contract addresses
    function getEventArtists(address _eventContract) 
        external 
        view 
        returns (address[] memory) 
    {
        return eventToArtists[_eventContract];
    }

    /// @notice Gets a range of artist contracts
    /// @param start Starting index in the artists array
    /// @param end Ending index in the artists array
    /// @return Array of artist contract addresses within the specified range
    function getArtists(uint256 start, uint256 end) 
        external 
        view 
        returns (address[] memory) 
    {
        require(start <= end && end < artists.length, "Invalid range");

        uint256 length = end - start + 1;
        address[] memory result = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = artists[start + i];
        }

        return result;
    }
}
