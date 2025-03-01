// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Migrations Contract
/// @author XAO Protocol Team
/// @notice This contract keeps track of migration history
/// @dev Implements a simple migrations tracking mechanism for deployment control
contract Migrations {
    /// @notice Address of the contract owner
    address public owner = msg.sender;
    /// @notice Last completed migration timestamp
    uint public last_completed_migration;

    /// @notice Restricts function access to the contract owner
    /// @dev Used as a modifier for owner-only functions
    modifier restricted() {
        require(
            msg.sender == owner,
            "This function is restricted to the contract's owner"
        );
        _;
    }

    /// @notice Sets the last completed migration
    /// @dev Used by the deployer to track migration progress
    /// @param completed The number of the migration that was completed
    function setCompleted(uint completed) public restricted {
        last_completed_migration = completed;
    }
}