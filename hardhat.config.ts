import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
    solidity: "0.8.17",
    networks: {
        hardhat: {
            forking: {
                url: "https://api.avax.network/ext/bc/C/rpc",
            },
        },
    },
};

export default config;
