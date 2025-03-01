// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IArtistContract {
    // Artist structure
    struct ArtistDetails {
        address artist;
        address parentContract;
        uint256 loadInTime;
        uint256 setTime;
        string rider;
        string legalText;
        uint256 guaranteeAmount;
        uint256 revenueShare;
        uint256 depositAmount;
        bool approvalRequired;
        bool isCancelled;
    }

    // Events
    event ArtistDetailsSet(address artist, uint256 setTime);
    event ContractSigned(address artist);
    event ArtistCancelled(address artist);
    event PaymentReceived(address artist, uint256 amount);
    event CancellationPenalty(address artist, uint256 penaltyAmount, uint256 penaltyPercentage);

    // Core functions
    function setArtistDetails(
        uint256 _loadInTime,
        uint256 _setTime,
        string memory _rider,
        string memory _legalText,
        uint256 _guaranteeAmount,
        uint256 _revenueShare
    ) external;

    function signContract() external;
    function cancelPerformance() external;
    function receivePayment() external;
    function withdrawDeposit() external;
}