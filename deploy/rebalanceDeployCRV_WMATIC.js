//const { ethers } = require("ethers");
const { ethers } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const fs = require("fs");

module.exports = async () => {
    console.log(network.config.chainId);
    const currNetworkConfig = networkConfig[network.config.chainId + 1];

    let args = [
        currNetworkConfig.uniswapRouterAddress,
        currNetworkConfig.uniswapPoolAddress,
        currNetworkConfig.aaveV3PoolAddress,
        currNetworkConfig.aaveVWMATICAddress,
        currNetworkConfig.aaveVCRVAddress,
        currNetworkConfig.aaveOracleAddress,
        currNetworkConfig.aaveAUSDCAddress,
        currNetworkConfig.ticksRange
    ];

    let usd = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.usdcAddress
    );
    let crv = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.crvAddress
    );
    let wmatic = await ethers.getContractAt(
        "WMATIC",
        currNetworkConfig.wmaticAddress
    );

    console.log("----------------------------------------------------");
    const Rebalance = await ethers.getContractFactory("ChamberV1_CRVWMATIC");
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
        currNetworkConfig.aaveVWETHAddress
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
        currNetworkConfig.aaveVWETHAddress
    );

    await rebalance.giveApprove(
        crv.address,
        currNetworkConfig.aaveV3PoolAddress
    );
    await rebalance.giveApprove(
        crv.address,
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

module.exports.tags = ["all", "rebalanceCRV_WMATIC"];
