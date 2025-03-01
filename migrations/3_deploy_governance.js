const XAOToken = artifacts.require("XAOToken");
const XAOStaking = artifacts.require("XAOStaking");
const XAOGovernance = artifacts.require("XAOGovernance");

module.exports = async function(deployer, network, accounts) {
  console.log("Deploying XAOGovernance...");
  
  // Get the deployed token and staking instances
  const xaoToken = await XAOToken.deployed();
  console.log("XAOToken address:", xaoToken.address);
  
  const xaoStaking = await XAOStaking.deployed();
  console.log("XAOStaking address:", xaoStaking.address);

  // Deploy XAOGovernance with optimized gas settings
  await deployer.deploy(
    XAOGovernance, 
    xaoToken.address, 
    xaoStaking.address, 
    { gas: 11000000 }
  );
  const xaoGovernance = await XAOGovernance.deployed();
  console.log("XAOGovernance deployed at:", xaoGovernance.address);
};
