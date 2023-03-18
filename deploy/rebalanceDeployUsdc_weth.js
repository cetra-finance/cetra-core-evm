//const { ethers } = require("ethers");
const { ethers } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const fs = require("fs");

module.exports = async () => {
    const currNetworkConfig = networkConfig[31341];

    let args = [
        currNetworkConfig.uniswapRouterAddress,
        currNetworkConfig.uniswapPoolAddress,
        currNetworkConfig.aaveV3PoolAddress,
        currNetworkConfig.aaveVWETHAddress,
        currNetworkConfig.aaveOracleAddress,
        currNetworkConfig.aaveAUSDCAddress,
        currNetworkConfig.ticksRange
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
    const Rebalance = await ethers.getContractFactory("ChamberV1Stable");
    const chamber = await Rebalance.deploy(...args);
    await chamber.deployed();

    await chamber.setLTV(
        currNetworkConfig.targetLTV,
        currNetworkConfig.minLTV,
        currNetworkConfig.maxLTV,
        currNetworkConfig.hedgeDev
    );

    await chamber
        .giveApprove(usd.address, currNetworkConfig.aaveV3PoolAddress);
    await chamber
        .giveApprove(usd.address, currNetworkConfig.aaveVWETHAddress);

    await chamber
        .giveApprove(weth.address, currNetworkConfig.aaveV3PoolAddress);
    await chamber
        .giveApprove(weth.address, currNetworkConfig.uniswapPoolAddress);
    await chamber
        .giveApprove(weth.address, currNetworkConfig.aaveVWETHAddress);

    console.log(`You have deployed an contract to ${chamber.address}`);
    console.log(
        `Verify with:\n npx hardhat verify --network matic ${
            chamber.address
        } ${args.toString().replace(/,/g, " ")}`
    );

    console.log("done");
};

module.exports.tags = ["all", "rebalanceUsdc_weth"];
