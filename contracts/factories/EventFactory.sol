// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../ParentEventContract.sol";

contract EventFactory is Ownable {
    // Fee for creating an event
    uint256 public eventCreationFee;

    // Array to track all created events
    address[] public events;

    // Mapping to check if an address is a created event
    mapping(address => bool) public isEvent;

    // Reference to the artist factory
    address public immutable artistFactory;

    event EventCreated(address indexed eventAddress, address indexed creator);
    event FeeUpdated(uint256 newFee);
    event FeesWithdrawn(uint256 amount);

    constructor(uint256 _eventCreationFee, address _artistFactory) {
        require(_artistFactory != address(0), "Invalid artist factory");
        eventCreationFee = _eventCreationFee;
        artistFactory = _artistFactory;
    }

    function createEvent() external payable returns (address) {
        require(msg.value >= eventCreationFee, "Insufficient fee");

        // Deploy new event contract with artist factory address
        ParentEventContract newEvent = new ParentEventContract(artistFactory);

        // Transfer ownership to creator
        newEvent.transferOwnership(msg.sender);

        // Record the new event
        events.push(address(newEvent));
        isEvent[address(newEvent)] = true;

        emit EventCreated(address(newEvent), msg.sender);

        return address(newEvent);
    }

    function updateEventCreationFee(uint256 _newFee) external onlyOwner {
        eventCreationFee = _newFee;
        emit FeeUpdated(_newFee);
    }

    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");

        (bool success, ) = owner().call{value: balance}("");
        require(success, "Fee withdrawal failed");

        emit FeesWithdrawn(balance);
    }

    function getEventCount() external view returns (uint256) {
        return events.length;
    }

    function getEvents(uint256 start, uint256 end) 
        external 
        view 
        returns (address[] memory) 
    {
        require(start <= end && end < events.length, "Invalid range");

        uint256 length = end - start + 1;
        address[] memory result = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = events[start + i];
        }

        return result;
    }
}