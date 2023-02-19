const networkConfig = {
    default: {
        name: "hardhat",
        keepersUpdateInterval: "30",
    },
    31337: {
        name: "fork",
        donorWalletAddress: "0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245",
        usdcAddress: "0x2791bca1f2de4661ed88a30c99a7a9449aa84174",
        wethAddress: "0x7ceb23fd6bc0add59e62ac25578270cff1b9f619",
        wmaticAddress: "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270",
        uniswapRouterAddress: "0xe592427a0aece92de3edee1f18e0157c05861564",
        uniswapPoolAddress: "0x86f1d8390222a3691c28938ec7404a1661e618e0",
        aaveWTG3Address: "0x1e4b7A6b903680eab0c5dAbcb8fD429cD2a9598c",
        aaveV3PoolAddress: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
        aaveVWETHAddress: "0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351",
        aaveVWMATICAddress: "0x4a1c3aD6Ed28a636ee1751C69071f6be75DEb8B8",
        aaveOracleAddress: "0xb023e699F5a33916Ea823A16485e259257cA8Bd1",
        targetLTV: "690000000000000000",
        minLTV: "600000000000000000",
        maxLTV: "750000000000000000",
        aaveAUSDCAddress: "0x625E7708f30cA75bfd92586e17077590C60eb4cD",
        hedgeDev: "200000000000000000",
    },
    137: {
        name: "matic",
        donorWalletAddress: "0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245",
        usdcAddress: "0x2791bca1f2de4661ed88a30c99a7a9449aa84174",
        wethAddress: "0x7ceb23fd6bc0add59e62ac25578270cff1b9f619",
        wmaticAddress: "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270",
        uniswapRouterAddress: "0xe592427a0aece92de3edee1f18e0157c05861564",
        uniswapPoolAddress: "0x86f1d8390222a3691c28938ec7404a1661e618e0",
        aaveWTG3Address: "0x1e4b7A6b903680eab0c5dAbcb8fD429cD2a9598c",
        aaveV3PoolAddress: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
        aaveVWETHAddress: "0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351",
        aaveVWMATICAddress: "0x4a1c3aD6Ed28a636ee1751C69071f6be75DEb8B8",
        aaveOracleAddress: "0xb023e699F5a33916Ea823A16485e259257cA8Bd1",
        targetLTV: "690000000000000000",
        minLTV: "600000000000000000",
        maxLTV: "750000000000000000",
        aaveAUSDCAddress: "0x625E7708f30cA75bfd92586e17077590C60eb4cD",
        hedgeDev: "200000000000000000",
    },
};

const developmentChains = ["hardhat", "fork"];

module.exports = {
    networkConfig,
    developmentChains,
};
