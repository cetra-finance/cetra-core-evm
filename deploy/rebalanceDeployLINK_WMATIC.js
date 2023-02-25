//const { ethers } = require("ethers");
const { ethers } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const fs = require("fs");

module.exports = async () => {
    console.log(network.config.chainId);
    const currNetworkConfig = networkConfig[network.config.chainId + 3];

    let args = [
        currNetworkConfig.uniswapRouterAddress,
        currNetworkConfig.uniswapPoolAddress,
        currNetworkConfig.aaveV3PoolAddress,
        currNetworkConfig.aaveVWMATICAddress,
        currNetworkConfig.aaveVLINKAddress,
        currNetworkConfig.aaveOracleAddress,
        currNetworkConfig.aaveAUSDCAddress,
        currNetworkConfig.ticksRange
    ];

    let usd = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.usdcAddress
    );
    let link = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.linkAddress
    );
    let wmatic = await ethers.getContractAt(
        "WMATIC",
        currNetworkConfig.wmaticAddress
    );

    console.log("----------------------------------------------------");
    const Rebalance = await ethers.getContractFactory("ChamberV1_LINKETH");
    const rebalance = await Rebalance.deploy(...args);
    await rebalance.deployed();

    await rebalance.setLTV(
        currNetworkConfig.targetLTV,
        currNetworkConfig.minLTV,
        currNetworkConfig.maxLTV,
        currNetworkConfig.hedgeDev
    );

    await rebalance.giveApprove(
        usd.address,
        currNetworkConfig.aaveV3PoolAddress
    );
    await rebalance.giveApprove(
        usd.address,
        currNetworkConfig.uniswapRouterAddress
    );
    await rebalance.giveApprove(
        usd.address,
        currNetworkConfig.uniswapPoolAddress
    );
    await rebalance.giveApprove(
        usd.address,
        currNetworkConfig.aaveVWMATICAddress
    );

    await rebalance.giveApprove(
        wmatic.address,
        currNetworkConfig.aaveV3PoolAddress
    );
    await rebalance.giveApprove(
        wmatic.address,
        currNetworkConfig.uniswapRouterAddress
    );
    await rebalance.giveApprove(
        wmatic.address,
        currNetworkConfig.uniswapPoolAddress
    );
    await rebalance.giveApprove(
        wmatic.address,
        currNetworkConfig.aaveVWMATICAddress
    );

    await rebalance.giveApprove(
        link.address,
        currNetworkConfig.aaveV3PoolAddress
    );
    await rebalance.giveApprove(
        link.address,
        currNetworkConfig.uniswapRouterAddress
    );

    console.log(`You have deployed an contract to ${rebalance.address}`);
    console.log(
        `Verify with:\n npx hardhat verify --network matic ${
            rebalance.address
        } ${args.toString().replace(/,/g, " ")}`
    );

    console.log("done");
};

module.exports.tags = ["all", "rebalanceLINK_WMATIC"];
