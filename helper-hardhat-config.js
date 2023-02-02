const networkConfig = {
    default: {
        name: "hardhat",
        keepersUpdateInterval: "30",
    },
    31337: {
        name: "fork",
        usdAddress: "0x7F5c764cBc14f9669B88837ca1490cCa17c31607",
        wethAddress: "0x4200000000000000000000000000000000000006",
        uniswapRouterAddress: "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45",
        uniswapPoolAddress: "0x85149247691df622eaF1a8Bd0CaFd40BC45154a9",
        aaveWTG3Address: "0x76D3030728e52DEB8848d5613aBaDE88441cbc59",
        aaveV3PoolAddress: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
        aaveVWETHAddress: "0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351",
        aaveOracleAddress: "0xD81eb3728a631871a7eBBaD631b5f424909f0c77",
        uniswapNFTManagerAddress: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
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