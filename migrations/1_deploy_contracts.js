// SPDX-License-Identifier: MIT
const XAOToken = artifacts.require("XAOToken");
const XAOGovernance = artifacts.require("XAOGovernance");
const XAOStaking = artifacts.require("XAOStaking");
const XAOTreasury = artifacts.require("XAOTreasury");
const ArtistFactory = artifacts.require("ArtistFactory");
const EventFactory = artifacts.require("EventFactory");
const EventExplorer = artifacts.require("EventExplorer");

module.exports = async function(deployer, network, accounts) {
  const deployerAccount = accounts[0];
  console.log("Deploying contracts with account:", deployerAccount);
  console.log("Network:", network);

  try {
    // Deploy core contracts first to optimize gas usage
    console.log("\nDeploying Core Contracts...");

    await deployer.deploy(XAOToken, { gas: 10000000 }); // Increased from 5M to 10M
    const xaoToken = await XAOToken.deployed();
    console.log("XAO Token deployed at:", xaoToken.address);

    await deployer.deploy(XAOStaking, xaoToken.address, { gas: 10000000 }); // Increased from 5M to 10M
    const xaoStaking = await XAOStaking.deployed();
    console.log("XAO Staking deployed at:", xaoStaking.address);

    await deployer.deploy(XAOGovernance, xaoToken.address, xaoStaking.address, { gas: 11000000 }); // Increased from 5.5M to 11M
    const xaoGovernance = await XAOGovernance.deployed();
    console.log("XAO Governance deployed at:", xaoGovernance.address);

    // Deploy Treasury with deployer and a dead address as signers to avoid duplicates
    const deadAddress = "0x000000000000000000000000000000000000dEaD";
    await deployer.deploy(
      XAOTreasury,
      xaoStaking.address,
      xaoGovernance.address,
      [deployerAccount, deadAddress], // Initial signers (deployer + dead address)
      2, // Min signers required
      { gas: 12000000 } // Increased from 6M to 12M
    );
    const xaoTreasury = await XAOTreasury.deployed();
    console.log("XAO Treasury deployed at:", xaoTreasury.address);

    console.log("\nDeploying Factory Contracts...");

    // Set initial event creation fee (0.1 ETH)
    const eventCreationFee = web3.utils.toWei("0.1", "ether");

    // Deploy factories with optimized gas
    await deployer.deploy(ArtistFactory, { gas: 12000000 }); // Increased from 6M to 12M
    const artistFactory = await ArtistFactory.deployed();
    console.log("ArtistFactory deployed at:", artistFactory.address);

    // Increased gas limit for EventFactory
    await deployer.deploy(EventFactory, eventCreationFee, artistFactory.address, { gas: 14000000 }); // Increased from 7M to 14M
    const eventFactory = await EventFactory.deployed();
    console.log("EventFactory deployed at:", eventFactory.address);

    // Update ArtistFactory's EventFactory reference
    await artistFactory.setEventFactory(eventFactory.address, { gas: 2000000 }); // Increased from 1M to 2M

    // Deploy EventExplorer last since it's not critical for core functionality
    await deployer.deploy(EventExplorer, { gas: 6000000 }); // Increased from 3M to 6M
    const eventExplorer = await EventExplorer.deployed();
    console.log("EventExplorer deployed at:", eventExplorer.address);

    console.log("\nDeployment Summary:");
    console.log("------------------");
    console.log("Network:", network);
    console.log("Deployer:", deployerAccount);
    console.log("XAO Token:", xaoToken.address);
    console.log("XAO Staking:", xaoStaking.address);
    console.log("XAO Governance:", xaoGovernance.address);
    console.log("XAO Treasury:", xaoTreasury.address);
    console.log("ArtistFactory:", artistFactory.address);
    console.log("EventFactory:", eventFactory.address);
    console.log("EventExplorer:", eventExplorer.address);
    console.log("Event Creation Fee:", web3.utils.fromWei(eventCreationFee, "ether"), "ETH");

  } catch (error) {
    console.error("\nDeployment failed:");
    console.error("Error:", error.message);
    console.error("Stack:", error.stack);
    throw error;
  }
};