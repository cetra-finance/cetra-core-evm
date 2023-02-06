const networkConfig = {
    default: {
        name: "hardhat",
        keepersUpdateInterval: "30",
    },
    31337: {
        name: "fork",
        usdcAddress: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
        wethAddress: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619",
        wmaticAddress: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
        uniswapRouterAddress: "0x4c60051384bd2d3c01bfc845cf5f4b44bcbe9de5",
        uniswapPoolAddress: "0x167384319B41F7094e62f7506409Eb38079AbfF8",
        aaveWTG3Address: "0x1e4b7A6b903680eab0c5dAbcb8fD429cD2a9598c",
        aaveV3PoolAddress: "0x794a61358d6845594f94dc1db02a252b5b4814ad",
        aaveVMATICAddress: "0x4a1c3ad6ed28a636ee1751c69071f6be75deb8b8",
        aaveOracleAddress: "0xb023e699F5a33916Ea823A16485e259257cA8Bd1",
        uniswapNFTManagerAddress: "0xc36442b4a4522e871399cd717abdd847ab11fe88",
        targetLTV: "670000000000000000",
        minLTV: 0.6 * 1e18,
        maxLTV: 0.75 * 1e18,
    },
};

const developmentChains = ["hardhat", "fork"];

module.exports = {
    networkConfig,
    developmentChains,
};