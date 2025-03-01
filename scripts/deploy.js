const hre = require("hardhat");

async function main() {
  // Deploy ParentEventContract
  const ParentEventContract = await hre.ethers.getContractFactory("ParentEventContract");
  const parentEventContract = await ParentEventContract.deploy();
  await parentEventContract.deployed();
  console.log("ParentEventContract deployed to:", parentEventContract.address);

  // Deploy ArtistContract with parent contract address and artist address
  const [owner, artist] = await hre.ethers.getSigners();
  const ArtistContract = await hre.ethers.getContractFactory("ArtistContract");
  const artistContract = await ArtistContract.deploy(parentEventContract.address, artist.address);
  await artistContract.deployed();
  console.log("ArtistContract deployed to:", artistContract.address);

  // Link the artist contract to parent contract
  await parentEventContract.linkArtistContract(artistContract.address);
  console.log("ArtistContract linked to ParentEventContract");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
