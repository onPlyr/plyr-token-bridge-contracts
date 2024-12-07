require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      evmVersion: "london",
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {
      forking: {
        url: "https://gwan-ssl.wandevs.org:46891",
        blockNumber: 31774713,
      },
    },
    localTest: {
      url: "http://127.0.0.1:8545/",
      accounts: [process.env.PK],
    },
    wanchainTestnet: {
      url: "https://gwan-ssl.wandevs.org:46891/",
      accounts: [process.env.PK],
      gasPrice: 10e9,
      minGasPrice: 10e9,
      gas: 8e6,
      maxPriorityFeePerGas: 1e9,
    },
    sepolia: {
      url: "https://ethereum-sepolia-rpc.publicnode.com",
      accounts: [process.env.PK],
    },
    fuji: {
      url: 'https://avalanche-fuji-c-chain-rpc.publicnode.com',
      accounts: [process.env.PK],
    },
    bscTestnet: {
      url: 'https://bsc-testnet-rpc.publicnode.com',
      accounts: [process.env.PK],
    },
    plyrTestnet: {
      url: "https://subnets.avax.network/plyr/testnet/rpc",
      accounts: [process.env.PK],
    }
  }
};
