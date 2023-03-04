//const { ethers } = require("ethers");
const { ethers } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const fs = require("fs");

module.exports = async () => {
    console.log(network.config.chainId);
    const currNetworkConfig = networkConfig[network.config.chainId];

    let args = [
        currNetworkConfig.uniswapRouterAddress,
        currNetworkConfig.uniswapPoolAddress,
        currNetworkConfig.aaveV3PoolAddress,
        currNetworkConfig.aaveVWETHAddress,
        currNetworkConfig.aaveOracleAddress,
        currNetworkConfig.aaveAUSDCAddress,
        currNetworkConfig.ticksRange,
    ];

    let usd = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.usdcAddress
    );
    let weth = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.wethAddress
    );

    console.log("----------------------------------------------------");
    // const Rebalance = await ethers.getContractFactory("ChamberV1VolStable");
    const rebalance = await ethers.getContractAt(
        "ChamberV1VolStable",
        "0x93e3b2e1e3837622156fecdc6e5472af31fe10bb"
    );
    // const rebalance = await Rebalance.deploy(...args);
    // await rebalance.deployed();

    await rebalance.setTicksRange(4100);

    // await rebalance.setLTV(
    //     currNetworkConfig.targetLTV,
    //     currNetworkConfig.minLTV,
    //     currNetworkConfig.maxLTV,
    //     currNetworkConfig.hedgeDev
    // );

    // await rebalance.giveApprove(
    //     usd.address,
    //     currNetworkConfig.aaveV3PoolAddress
    // );
    // await rebalance.giveApprove(
    //     usd.address,
    //     currNetworkConfig.uniswapRouterAddress
    // );
    // await rebalance.giveApprove(
    //     usd.address,
    //     currNetworkConfig.uniswapPoolAddress
    // );
    // await rebalance.giveApprove(
    //     usd.address,
    //     currNetworkConfig.aaveVWETHAddress
    // );

    // await rebalance.giveApprove(
    //     weth.address,
    //     currNetworkConfig.aaveV3PoolAddress
    // );
    // await rebalance.giveApprove(
    //     weth.address,
    //     currNetworkConfig.uniswapRouterAddress
    // );
    // await rebalance.giveApprove(
    //     weth.address,
    //     currNetworkConfig.uniswapPoolAddress
    // );
    // await rebalance.giveApprove(
    //     weth.address,
    //     currNetworkConfig.aaveVWETHAddress
    // );

    console.log(`You have deployed an contract to ${rebalance.address}`);
    console.log(
        `Verify with:\n npx hardhat verify --network arbitrum ${
            rebalance.address
        } ${args.toString().replace(/,/g, " ")}`
    );

    console.log("done");
};

module.exports.tags = ["all", "ChamberV1VolStable"];
