const XAOStaking = artifacts.require("XAOStaking");
const XAOGovernance = artifacts.require("XAOGovernance");
const XAOTreasury = artifacts.require("XAOTreasury");

module.exports = async function(deployer, network, accounts) {
  console.log("Deploying XAOTreasury...");
  
  // Get the deployed staking and governance instances
  const xaoStaking = await XAOStaking.deployed();
  console.log("XAOStaking address:", xaoStaking.address);
  
  const xaoGovernance = await XAOGovernance.deployed();
  console.log("XAOGovernance address:", xaoGovernance.address);

  // Deploy XAOTreasury with optimized gas settings
  const deadAddress = "0x000000000000000000000000000000000000dEaD";
  await deployer.deploy(
    XAOTreasury, 
    xaoStaking.address, 
    xaoGovernance.address,
    [accounts[0], deadAddress], // Initial signers (deployer + dead address)
    2, // Min signers required
    { gas: 12000000 }
  );
  const xaoTreasury = await XAOTreasury.deployed();
  console.log("XAOTreasury deployed at:", xaoTreasury.address);
};
