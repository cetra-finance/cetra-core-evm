//const { ethers } = require("ethers");
const { ethers } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const fs = require("fs");

module.exports = async () => {
    console.log(network.config.chainId);
    const currNetworkConfig = networkConfig[network.config.chainId];

    usd = await ethers.getContractAt("IERC20", currNetworkConfig.usdcAddress);
    snx = await ethers.getContractAt("IERC20", currNetworkConfig.snxAddress);
    weth = await ethers.getContractAt("IERC20", currNetworkConfig.wethAddress);
    sonne = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.sonneAddress
    );
    soUSDC = await ethers.getContractAt("ICErc20", currNetworkConfig.soUSDC);
    soSNX = await ethers.getContractAt("ICErc20", currNetworkConfig.soSNX);
    soWETH = await ethers.getContractAt("ICErc20", currNetworkConfig.soWETH);

    console.log("deploying swapHelper");
    const SwapHelperFactory = await ethers.getContractFactory(
        "WETHSNX_swapHelper"
    );
    const swapHelper = await SwapHelperFactory.deploy();
    await swapHelper.deployed();
    console.log("deployed swapHelper");
    console.log("----------------------------------------------------");
    console.log("deploying chamber");
    const chamberFactory = await ethers.getContractFactory(
        "ChamberV1_WETHSNX_Sonne"
    );
    chamber = await chamberFactory.deploy(
        swapHelper.address,
        currNetworkConfig.ticksRange
    );
    await chamber.deployed();
    console.log("deployed chamber");

    await chamber.setLTV(
        currNetworkConfig.targetLTV,
        currNetworkConfig.minLTV,
        currNetworkConfig.maxLTV,
        currNetworkConfig.hedgeDev
    );

    await chamber.giveApprove(
        usd.address,
        currNetworkConfig.uniswapRouterAddress
    );
    await chamber.giveApprove(usd.address, currNetworkConfig.soUSDC);

    await chamber.giveApprove(
        snx.address,
        currNetworkConfig.uniswapRouterAddress
    );
    await chamber.giveApprove(
        snx.address,
        currNetworkConfig.uniswapPoolAddress
    );
    await chamber.giveApprove(snx.address, currNetworkConfig.soSNX);

    await chamber.giveApprove(
        weth.address,
        currNetworkConfig.uniswapRouterAddress
    );
    await chamber.giveApprove(
        currNetworkConfig.sonneAddress,
        currNetworkConfig.veloRouterAddress
    );
    await chamber.giveApprove(weth.address, currNetworkConfig.soWETH);
    let args = [
        "0x93e3B2E1E3837622156FEcdC6e5472AF31fE10Bb",
        currNetworkConfig.ticksRange,
    ];
    console.log(
        `You have deployed an contract to 0x4f46191bc4865813cbd2ea583046bea165b7af8f`
    );
    console.log(
        `Verify with:\n npx hardhat verify --network optimism 0x4f46191bc4865813cbd2ea583046bea165b7af8f ${args
            .toString()
            .replace(/,/g, " ")}`
    );

    console.log("done");
};

module.exports.tags = ["all", "rebalanceWETH_SNX"];
