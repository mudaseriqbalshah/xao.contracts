require('dotenv').config();
const HDWalletProvider = require('@truffle/hdwallet-provider');

module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*"
    },
    sepolia: {
      provider: () => new HDWalletProvider(
        process.env.MNEMONIC,
        process.env.SEPOLIA_RPC_URL
      ),
      network_id: 11155111,
      gas: process.env.GAS_LIMIT || 5500000,
      gasPrice: process.env.GAS_PRICE || 20000000000,
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true
    },
    sepolia_base: {
      provider: () => new HDWalletProvider(
        process.env.PRIVATE_KEY,
        process.env.SEPOLIA_BASE_RPC_URL
      ),
      network_id: 84532,
      gas: 15000000,
      gasPrice: 15000000000,
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true,
      networkCheckTimeout: 10000,
      // verify: {
      //   apiUrl: 'https://api-sepolia.basescan.org/api',
      //   apiKey: "17EM3GTF7UXCJGDAJP8UIYVTXHQGHEI5UN",
      //   explorerUrl: 'https://sepolia.basescan.org/address',
      // }
    }
  },
  compilers: {
    solc: {
      version: "0.8.19",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }
  },
  plugins: ['truffle-plugin-verify'],
  api_keys: {
    basescan: process.env.BASESCAN_API_KEY
  },
  verify: {
    proxy: {
      host: 'https://api-sepolia.basescan.org'
    }
  }
};