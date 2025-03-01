const XAOToken = artifacts.require("XAOToken");

module.exports = async function(deployer, network, accounts) {
  // Deploy XAO Token
  await deployer.deploy(XAOToken);
  const xaoToken = await XAOToken.deployed();
  console.log("XAO Token deployed at:", xaoToken.address);
};