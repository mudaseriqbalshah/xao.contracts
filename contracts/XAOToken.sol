// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/// @title XAO Token Contract
/// @author XAO Protocol Team
/// @notice This is the main token contract for the XAO ecosystem
/// @dev Implementation of the XAO token with pausable and permit functionality
contract XAOToken is ERC20, ERC20Permit, Pausable, Ownable {
    using SafeMath for uint256;

    /// @notice The total initial supply of XAO tokens (1 billion)
    /// @dev Stored as a constant with 18 decimal places
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;

    /// @notice The portion of tokens allocated to the team (20%)
    uint256 public constant TEAM_ALLOCATION = INITIAL_SUPPLY * 20 / 100;

    /// @notice The vesting cliff period for team tokens
    uint256 public constant VESTING_CLIFF = 180 days;

    /// @notice The total vesting duration for team tokens
    uint256 public constant VESTING_DURATION = 720 days;

    /// @notice The minimum delay between transfers (anti flash loan)
    uint256 public constant TRANSFER_DELAY = 1 hours;

    /// @notice Struct to track team member vesting details
    struct TeamMember {
        uint256 allocation;
        uint256 claimed;
        uint256 vestingStart;
        bool isActive;
    }

    /// @notice Mapping of team member addresses to their vesting details
    mapping(address => TeamMember) public teamMembers;

    /// @notice Mapping to track last transfer timestamp for each address
    mapping(address => uint256) public lastTransferTime;

    /// @notice Mapping to track addresses exempt from transfer delay
    mapping(address => bool) public transferDelayExempt;

    /// @notice Total amount of team tokens allocated
    uint256 public totalTeamAllocated;

    /// @notice Emitted when a team member is added
    event TeamMemberAdded(address indexed member, uint256 allocation);

    /// @notice Emitted when team tokens are claimed
    event TeamTokensClaimed(address indexed member, uint256 amount);

    /// @notice Emitted when transfer delay exemption is updated
    event TransferDelayExemptionUpdated(address indexed account, bool exempt);

    /// @notice Creates a new XAO token contract
    /// @dev Initializes the ERC20 token with name, symbol, and mints initial supply
    constructor() ERC20("XAO Token", "XAO") ERC20Permit("XAO Token") {
        // Mint initial supply minus team allocation to deployer
        _mint(msg.sender, INITIAL_SUPPLY.sub(TEAM_ALLOCATION));
    }

    /// @notice Returns the total token supply including reserved team allocation
    /// @dev Overrides ERC20 totalSupply() to include both circulating and reserved tokens
    function totalSupply() public view virtual override returns (uint256) {
        return INITIAL_SUPPLY;
    }

    /// @notice Adds a new team member with token allocation
    /// @dev Can only be called by the contract owner
    /// @param member Address of the team member
    /// @param allocation Amount of tokens allocated to the member
    function addTeamMember(address member, uint256 allocation) external onlyOwner {
        require(member != address(0), "Invalid address");
        require(!teamMembers[member].isActive, "Already a team member");
        require(allocation > 0, "Invalid allocation");
        require(totalTeamAllocated.add(allocation) <= TEAM_ALLOCATION, "Exceeds team allocation");

        teamMembers[member] = TeamMember({
            allocation: allocation,
            claimed: 0,
            vestingStart: block.timestamp,
            isActive: true
        });

        totalTeamAllocated = totalTeamAllocated.add(allocation);
        emit TeamMemberAdded(member, allocation);
    }

    /// @notice Claims vested team tokens
    /// @dev Transfers available vested tokens to the team member
    function claimTeamTokens() external {
        TeamMember storage teamMember = teamMembers[msg.sender];
        require(teamMember.isActive, "Not a team member");
        require(
            block.timestamp >= teamMember.vestingStart.add(VESTING_CLIFF),
            "Still in cliff period"
        );

        uint256 vestedAmount = calculateVestedAmount(msg.sender);
        uint256 claimableAmount = vestedAmount.sub(teamMember.claimed);
        require(claimableAmount > 0, "No tokens to claim");

        teamMember.claimed = teamMember.claimed.add(claimableAmount);
        _mint(msg.sender, claimableAmount);

        emit TeamTokensClaimed(msg.sender, claimableAmount);
    }

    /// @notice Calculates vested tokens for a team member
    /// @dev Takes into account cliff and linear vesting schedule
    /// @param member Address of the team member
    /// @return Amount of tokens vested
    function calculateVestedAmount(address member) public view returns (uint256) {
        TeamMember storage teamMember = teamMembers[member];
        if (!teamMember.isActive) return 0;

        if (block.timestamp < teamMember.vestingStart.add(VESTING_CLIFF)) {
            return 0;
        }

        if (block.timestamp >= teamMember.vestingStart.add(VESTING_DURATION)) {
            return teamMember.allocation;
        }

        return teamMember.allocation.mul(
            block.timestamp.sub(teamMember.vestingStart)
        ).div(VESTING_DURATION);
    }

    /// @notice Sets transfer delay exemption status for an address
    /// @dev Can only be called by the contract owner
    /// @param account Address to update exemption status
    /// @param exempt Whether the address should be exempt from transfer delays
    function setTransferDelayExempt(address account, bool exempt) external onlyOwner {
        transferDelayExempt[account] = exempt;
        emit TransferDelayExemptionUpdated(account, exempt);
    }

    /// @notice Pauses all token transfers
    /// @dev Can only be called by the contract owner
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses all token transfers
    /// @dev Can only be called by the contract owner
    function unpause() public onlyOwner {
        _unpause();
    }

    /// @notice Hook that is called before any transfer of tokens
    /// @dev Ensures transfers cannot occur while paused and enforces transfer delay
    /// @param from The address tokens are transferred from
    /// @param to The address tokens are transferred to
    /// @param amount The amount of tokens to be transferred
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(!paused(), "Token transfer paused");

        // Check transfer delay for non-exempt addresses and non-minting transfers
        if (from != address(0) && !transferDelayExempt[from]) {
            require(
                block.timestamp >= lastTransferTime[from].add(TRANSFER_DELAY),
                "Transfer delay not met"
            );
        }

        super._beforeTokenTransfer(from, to, amount);

        // Update last transfer time after successful transfer
        if (from != address(0) && !transferDelayExempt[from]) {
            lastTransferTime[from] = block.timestamp;
        }
    }
}