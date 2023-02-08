/**
 * @type import('hardhat/config').HardhatUserConfig
 */

require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-deploy");
require("@nomicfoundation/hardhat-network-helpers");
require("hardhat-gas-reporter");
require('hardhat-contract-sizer');
require("hardhat-tracer");

require("dotenv").config();

const CUSTOM_RPC_URL = process.env.CUSTOM_RPC_URL || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "";

module.exports = {
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            chainId: 31337,
           forking: {
               url: CUSTOM_RPC_URL,
                blockNumber: 38980835
           }
        }
    },
    etherscan: {
        apiKey: ETHERSCAN_API_KEY
    },
    namedAccounts: {
        deployer: {
            default: 0, // here this will by default take the first account as deployer
            1: 0, // similarly on mainnet it will take the first account as deployer. Note though that depending on how hardhat network are configured, the account 0 on one network can be different than on another
        },
        feeCollector: {
            default: 1,
        },
    },
    solidity: {
        compilers: [
           {
            version: "0.8.17",
            },
            {
            version: "0.8.10",
            }
        ],
        settings: {
           optimizer: {
             runs: 100,
             enabled: true
           }
         }
    },
    mocha: {
        timeout: 10000000,
    },
    gasReporter: {
      enabled: false,
      gasPrice: 10,
      currency: 'USD',
      coinmarketcap: '2f0fe43a-0f3d-40a6-8558-ddd3625bfd6b',
   }
};