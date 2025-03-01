// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IArtistContract.sol";
import "./interfaces/IParentEventContract.sol";

/// @title Artist Contract
/// @author XAO Protocol Team
/// @notice This contract manages artist details, performance agreements, and cancellation terms
/// @dev Implements artist-specific functionality with cancellation penalties and payment processing
contract ArtistContract is IArtistContract, Ownable, ReentrancyGuard {
    /// @notice Artist contract state variables
    ArtistDetails public artistDetails;
    /// @notice Flag indicating if the contract has been signed by the artist
    bool public isContractSigned;

    /// @notice Cancellation windows and penalties constants
    /// @dev Time windows and corresponding penalty percentages for cancellations
    uint256 public constant EARLY_CANCEL_WINDOW = 30 days;
    uint256 public constant LATE_CANCEL_WINDOW = 7 days;
    uint256 public constant EARLY_CANCEL_PENALTY = 10; // 10%
    uint256 public constant LATE_CANCEL_PENALTY = 50;  // 50%
    uint256 public constant VERY_LATE_CANCEL_PENALTY = 100; // 100%

    /// @notice Constructor initializes artist contract with parent contract and artist address
    /// @param _parentContract Address of the parent event contract
    /// @param _artist Address of the artist
    constructor(address _parentContract, address _artist) {
        artistDetails.parentContract = _parentContract;
        artistDetails.artist = _artist;
        isContractSigned = false;
    }

    /// @notice Restricts function access to the artist only
    modifier onlyArtist() {
        require(msg.sender == artistDetails.artist, "Only artist can call");
        _;
    }

    /// @notice Ensures contract has been signed before certain operations
    modifier onlySigned() {
        require(isContractSigned, "Contract not signed");
        _;
    }

    /// @notice Sets the initial artist performance details
    /// @dev Can only be called by contract owner (parent event contract)
    /// @param _loadInTime Time when artist should arrive for setup
    /// @param _setTime Time when performance begins
    /// @param _rider Technical and hospitality requirements
    /// @param _legalText Legal agreement text
    /// @param _guaranteeAmount Guaranteed payment amount
    /// @param _revenueShare Percentage of revenue sharing
    function setArtistDetails(
        uint256 _loadInTime,
        uint256 _setTime,
        string memory _rider,
        string memory _legalText,
        uint256 _guaranteeAmount,
        uint256 _revenueShare
    ) external override onlyOwner {
        require(_loadInTime < _setTime, "Invalid times");
        require(_revenueShare <= 100, "Invalid revenue share");

        artistDetails.loadInTime = _loadInTime;
        artistDetails.setTime = _setTime;
        artistDetails.rider = _rider;
        artistDetails.legalText = _legalText;
        artistDetails.guaranteeAmount = _guaranteeAmount;
        artistDetails.revenueShare = _revenueShare;

        emit ArtistDetailsSet(artistDetails.artist, _setTime);
    }

    /// @notice Artist signs the contract
    /// @dev Can only be called once by the artist
    function signContract() external override onlyArtist {
        require(!isContractSigned, "Contract already signed");
        isContractSigned = true;
        emit ContractSigned(artistDetails.artist);
    }

    /// @notice Calculates cancellation penalty based on timing
    /// @dev Internal function to determine penalty percentage
    /// @return Penalty percentage based on time until event
    function calculateCancellationPenalty() internal view returns (uint256) {
        uint256 timeToEvent = artistDetails.setTime - block.timestamp;

        if (timeToEvent >= EARLY_CANCEL_WINDOW) {
            return EARLY_CANCEL_PENALTY;
        } else if (timeToEvent >= LATE_CANCEL_WINDOW) {
            return LATE_CANCEL_PENALTY;
        } else {
            return VERY_LATE_CANCEL_PENALTY;
        }
    }

    /// @notice Allows artist to cancel their performance
    /// @dev Applies appropriate penalty based on cancellation timing
    function cancelPerformance() external override onlyArtist onlySigned {
        require(!artistDetails.isCancelled, "Already cancelled");
        require(block.timestamp < artistDetails.setTime, "Event already occurred");

        uint256 penaltyPercentage = calculateCancellationPenalty();
        uint256 penaltyAmount = 0;

        // Calculate penalty from deposit if exists
        if (artistDetails.depositAmount > 0) {
            penaltyAmount = (artistDetails.depositAmount * penaltyPercentage) / 100;
            uint256 refundAmount = artistDetails.depositAmount - penaltyAmount;

            if (refundAmount > 0) {
                artistDetails.depositAmount = 0;
                (bool success, ) = artistDetails.artist.call{value: refundAmount}("");
                require(success, "Refund failed");
            }
        }

        artistDetails.isCancelled = true;
        emit ArtistCancelled(artistDetails.artist);
        emit CancellationPenalty(artistDetails.artist, penaltyAmount, penaltyPercentage);
    }

    /// @notice Processes payment to artist
    /// @dev Can only be called by artist after performance confirmation
    function receivePayment() external override onlyArtist onlySigned nonReentrant {
        require(!artistDetails.isCancelled, "Performance cancelled");

        IParentEventContract parentContract = IParentEventContract(artistDetails.parentContract);
        uint256 paymentAmount = artistDetails.guaranteeAmount;

        parentContract.processPayment(payable(artistDetails.artist), paymentAmount);
        emit PaymentReceived(artistDetails.artist, paymentAmount);
    }

    /// @notice Allows artist to withdraw their deposit
    /// @dev Only available if performance hasn't been cancelled
    function withdrawDeposit() external override onlyArtist onlySigned nonReentrant {
        require(!artistDetails.isCancelled, "Performance cancelled");
        require(artistDetails.depositAmount > 0, "No deposit to withdraw");

        uint256 amount = artistDetails.depositAmount;
        artistDetails.depositAmount = 0;

        (bool success, ) = artistDetails.artist.call{value: amount}("");
        require(success, "Withdrawal failed");
    }

    /// @notice Retrieves full artist contract details
    /// @return Complete ArtistDetails struct
    function getArtistDetails() external view returns (ArtistDetails memory) {
        return artistDetails;
    }

    /// @notice Returns the contract's cancellation terms
    /// @return earlyWindow Early cancellation window duration
    /// @return lateWindow Late cancellation window duration
    /// @return earlyPenalty Early cancellation penalty percentage
    /// @return latePenalty Late cancellation penalty percentage
    /// @return veryLatePenalty Very late cancellation penalty percentage
    function getCancellationTerms() external pure returns (
        uint256 earlyWindow,
        uint256 lateWindow,
        uint256 earlyPenalty,
        uint256 latePenalty,
        uint256 veryLatePenalty
    ) {
        return (
            EARLY_CANCEL_WINDOW,
            LATE_CANCEL_WINDOW,
            EARLY_CANCEL_PENALTY,
            LATE_CANCEL_PENALTY,
            VERY_LATE_CANCEL_PENALTY
        );
    }

    /// @notice Receives ETH deposits
    /// @dev Automatically updates the contract's deposit amount
    receive() external payable {
        artistDetails.depositAmount += msg.value;
    }
}