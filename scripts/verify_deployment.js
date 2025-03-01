const ParentEventContract = artifacts.require("ParentEventContract");
const ArtistContract = artifacts.require("ArtistContract");

module.exports = async function(callback) {
  try {
    // Get deployed contract instances
    const parentContract = await ParentEventContract.deployed();
    const artistContract = await ArtistContract.deployed();
    
    console.log("\nVerifying contract deployment and linkage...");
    console.log("ParentEventContract address:", parentContract.address);
    console.log("ArtistContract address:", artistContract.address);

    // Check if artist contract is linked
    const isLinked = await parentContract.isArtistLinked(artistContract.address);
    console.log("\nArtist Contract Linkage Status:", isLinked);

    // Get artist details from the artist contract
    const artistDetails = await artistContract.getArtistDetails();
    console.log("\nArtist Contract Details:");
    console.log("Parent Contract Address:", artistDetails.parentContract);
    console.log("Artist Address:", artistDetails.artist);

    console.log("\nVerification complete!");
    callback();
  } catch (error) {
    console.error("\nError during verification:", error);
    callback(error);
  }
};
