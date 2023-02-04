const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Basic tests new", function () {
    let owner, _, user1, user2;
    let ourRebalance, usd, weth, uniPositionManager;

    before(async () => {
        console.log("DEPLOYING VAULT, FUNDING USER ACCOUNTS...");
        const currNetworkConfig = networkConfig[network.config.chainId];
        accounts = await ethers.getSigners();
        owner = accounts[0];
        user1 = accounts[1];
        user2 = accounts[2];

        usd = await ethers.getContractAt("ERC20", currNetworkConfig.usdAddress);
        weth = await ethers.getContractAt(
            "ERC20",
            currNetworkConfig.wethAddress
        );
        uniPositionManager = await ethers.getContractAt(
            "INonfungiblePositionManager",
            currNetworkConfig.uniswapNFTManagerAddress
        );

        const OurRebalance = await ethers.getContractFactory("Rebalance1");
        ourRebalance = await OurRebalance.deploy(
            currNetworkConfig.usdAddress,
            currNetworkConfig.wethAddress,
            currNetworkConfig.uniswapRouterAddress,
            currNetworkConfig.uniswapPoolAddress,
            currNetworkConfig.aaveWTG3Address,
            currNetworkConfig.aaveV3PoolAddress,
            currNetworkConfig.aaveVWETHAddress,
            currNetworkConfig.aaveOracleAddress,
            currNetworkConfig.uniswapNFTManagerAddress
            //currNetworkConfig.targetLTV
        );
        
        await ourRebalance.deployed();

        await helpers.impersonateAccount(
            "0xebe80f029b1c02862b9e8a70a7e5317c06f62cae"
        );
        let donorWallet = await ethers.getSigner(
            "0xebe80f029b1c02862b9e8a70a7e5317c06f62cae"
        );

        await usd
            .connect(donorWallet)
            .transfer(owner.address, 1000 * 1000 * 1000 * 1000);
        await usd
            .connect(donorWallet)
            .transfer(user1.address, 2000 * 1000 * 1000 * 1000);
        await usd
            .connect(donorWallet)
            .transfer(user2.address, 2500 * 1000 * 1000 * 1000);

        await usd
            .connect(owner)
            .approve(ourRebalance.address, 1000 * 1000 * 1000 * 1000 * 1000);
        await usd
            .connect(user1)
            .approve(ourRebalance.address, 1000 * 1000 * 1000 * 1000 * 1000);
        await usd
            .connect(user2)
            .approve(ourRebalance.address, 1000 * 1000 * 1000 * 1000 * 1000);

        await ourRebalance.connect(owner).giveAllApproves();

        console.log(`Owner's address is ${owner.address}`);
        console.log(
            "--------------------------------------------------------------------"
        );
    });

    it("full circuit mint", async function () {
        console.log("OWNER DEPOSITS 1000000000");
        await ourRebalance.connect(owner).mintLiquidity(1000 * 1000 * 1000);
        console.log(await ourRebalance.calculateVirtPositionReserves());
        console.log("USER1 DEPOSITS 1500000000");
        await ourRebalance.connect(user1).mintLiquidity(1500 * 1000 * 1000);
        console.log("USER2 DEPOSITS 2500000000");
        await ourRebalance.connect(user2).mintLiquidity(2500 * 1000 * 1000);
        console.log("USER2 DEPOSITS 2500000000");
        await ourRebalance.connect(user2).mintLiquidity(2500 * 1000 * 1000);
        console.log("USER1 DEPOSITS 1500000000");
        await ourRebalance.connect(user1).mintLiquidity(1500 * 1000 * 1000);

        let positionId = await ourRebalance.getLiquidityTokenId();
        let position = await uniPositionManager.positions(positionId);
        console.log("The uniswap position is");
        console.log(position);

        console.log(
            `Total amount of shares minted is ${await ourRebalance.totalSupply()}`
        );
        console.log("BALANCE AND SHARESWORTH OF OWNER are");
        console.log(await ourRebalance.balanceOf(owner.address));
        console.log(
            await ourRebalance.sharesWorth(
                await ourRebalance.balanceOf(owner.address)
            )
        );
        console.log("BALANCE AND SHARESWORTH OF USER1 are");
        console.log(await ourRebalance.balanceOf(user1.address));
        console.log(
            await ourRebalance.sharesWorth(
                await ourRebalance.balanceOf(user1.address)
            )
        );
        console.log("BALANCE AND SHARESWORTH OF USER2 are");
        console.log(await ourRebalance.balanceOf(user2.address));
        console.log(
            await ourRebalance.sharesWorth(
                await ourRebalance.balanceOf(user2.address)
            )
        );
        console.log("TOKENS LEFT IN CONTRACT");
        console.log(await usd.balanceOf(ourRebalance.address));
        console.log(await weth.balanceOf(ourRebalance.address));
        console.log("TOKENS IN UNI POSITION");
        console.log(await ourRebalance.calculateCurrentPositionReserves());
        console.log("-----------------------------------------------------");
    });

    // it("full circuit withdraw", async function () {
    //     let user1Bal = await ourRebalance.balanceOf(owner.address)
    //     console.log(user1Bal);
    //     await ourRebalance.connect(owner).withdraw(user1Bal);
    // })
});

// 205922298
// 2188100073