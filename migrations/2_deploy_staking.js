const XAOToken = artifacts.require("XAOToken");
const XAOStaking = artifacts.require("XAOStaking");

module.exports = async function(deployer, network, accounts) {
  console.log("Deploying XAOStaking...");
  
  // Get the deployed XAOToken instance
  const xaoToken = await XAOToken.deployed();
  console.log("XAOToken address:", xaoToken.address);

  // Deploy XAOStaking with optimized gas settings
  await deployer.deploy(XAOStaking, xaoToken.address, { gas: 10000000 });
  const xaoStaking = await XAOStaking.deployed();
  console.log("XAOStaking deployed at:", xaoStaking.address);
};
