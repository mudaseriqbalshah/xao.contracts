require("@nomiclabs/hardhat-ethers");
require("@nomicfoundation/hardhat-verify");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    sepolia_base: {
      url: process.env.SEPOLIA_BASE_RPC_URL || "https://sepolia.base.org",
      accounts: [process.env.PRIVATE_KEY].filter(Boolean),
      chainId: 84532,
    }
  },
  etherscan: {
    apiKey: {
      "sepolia-base": process.env.BASESCAN_API_KEY
    },
    customChains: [
      {
        network: "sepolia-base",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org"
        }
      }
    ]
  },
  sourcify: {
    enabled: true
  }
};