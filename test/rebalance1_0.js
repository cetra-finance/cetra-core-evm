const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Basic tests new", function () {
    let owner, _, user1, user2;
    let usd, weth;

    before(async () => {
        console.log("DEPLOYING VAULT, FUNDING USER ACCOUNTS...");
        const currNetworkConfig = networkConfig[network.config.chainId];
        accounts = await ethers.getSigners();
        owner = accounts[0];
        user1 = accounts[1];
        user2 = accounts[2];
        usd = await ethers.getContractAt(
            "ERC20",
            currNetworkConfig.usdcAddress
        );
        weth = await ethers.getContractAt(
            "ERC20",
            currNetworkConfig.wethAddress
        );
        wmatic = await ethers.getContractAt(
            "ERC20",
            currNetworkConfig.wmaticAddress
        );
        const chamberFactory = await ethers.getContractFactory("ChamberV1");
        chamber = await chamberFactory.deploy(
            currNetworkConfig.uniswapRouterAddress,
            currNetworkConfig.uniswapPoolAddress,
            currNetworkConfig.aaveWTG3Address,
            currNetworkConfig.aaveV3PoolAddress,
            currNetworkConfig.aaveVWETHAddress,
            currNetworkConfig.aaveVWMATICAddress,
            currNetworkConfig.aaveOracleAddress,
            currNetworkConfig.aaveAUSDCAddress
        );
        await chamber.setLTV(
            currNetworkConfig.targetLTV,
            currNetworkConfig.minLTV,
            currNetworkConfig.maxLTV
        );

        await chamber.deployed();

        await helpers.impersonateAccount(currNetworkConfig.donorWalletAddress);
        let donorWallet = await ethers.getSigner(
            currNetworkConfig.donorWalletAddress
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
            .approve(chamber.address, 1000 * 1000 * 1000 * 1000 * 1000);
        await usd
            .connect(user1)
            .approve(chamber.address, 1000 * 1000 * 1000 * 1000 * 1000);
        await usd
            .connect(user2)
            .approve(chamber.address, 1000 * 1000 * 1000 * 1000 * 1000);

        await chamber.connect(owner).giveApprove(usd.address, currNetworkConfig.aaveV3PoolAddress);
        await chamber.connect(owner).giveApprove(usd.address, currNetworkConfig.uniswapRouterAddress);
        await chamber.connect(owner).giveApprove(usd.address, currNetworkConfig.uniswapPoolAddress);
        await chamber.connect(owner).giveApprove(usd.address, currNetworkConfig.aaveVWETHAddress);

        await chamber.connect(owner).giveApprove(weth.address, currNetworkConfig.aaveV3PoolAddress);
        await chamber.connect(owner).giveApprove(weth.address, currNetworkConfig.uniswapRouterAddress);
        await chamber.connect(owner).giveApprove(weth.address, currNetworkConfig.uniswapPoolAddress);
        await chamber.connect(owner).giveApprove(weth.address, currNetworkConfig.aaveVWETHAddress);

        await chamber.connect(owner).giveApprove(wmatic.address, currNetworkConfig.aaveV3PoolAddress);
        await chamber.connect(owner).giveApprove(wmatic.address, currNetworkConfig.uniswapRouterAddress);

        console.log(`Owner's address is ${owner.address}`);
        console.log(
            "--------------------------------------------------------------------"
        );
    });

    it("full circuit of mints", async function () {
        console.log("OWNER DEPOSITS 1000$");
        await chamber.connect(owner).mint(1000 * 1000 * 1000);
        console.log("LTV IS");
        console.log(await chamber.currentLTV());
        console.log("IN POOL");
        console.log(await chamber.calculateCurrentPositionReserves());
        console.log("USER1 DEPOSITS 1500$");
        await chamber.connect(user1).mint(1500 * 1000 * 1000);
        console.log("LTV IS");
        console.log(await chamber.currentLTV());
        console.log("USER2 DEPOSITS 2500$");
        await chamber.connect(user2).mint(2500 * 1000 * 1000);
        console.log("LTV IS");
        console.log(await chamber.currentLTV());
        console.log("USER2 DEPOSITS 2500$");
        await chamber.connect(user2).mint(2500 * 1000 * 1000);
        console.log("LTV IS");
        console.log(await chamber.currentLTV());
        console.log("USER1 DEPOSITS 1500$");
        await chamber.connect(user1).mint(1500 * 1000 * 1000);
        console.log("LTV IS");
        console.log(await chamber.currentLTV());

        console.log(
            `Total amount of shares minted is ${await chamber.s_totalShares()}`
        );
        console.log("BALANCE AND SHARESWORTH OF OWNER are");
        console.log(await chamber.s_userShares(owner.address));
        console.log(
            await chamber.sharesWorth(await chamber.s_userShares(owner.address))
        );
        console.log("BALANCE AND SHARESWORTH OF USER1 are");
        console.log(await chamber.s_userShares(user1.address));
        console.log(
            await chamber.sharesWorth(await chamber.s_userShares(user1.address))
        );
        console.log("BALANCE AND SHARESWORTH OF USER2 are");
        console.log(await chamber.s_userShares(user2.address));
        console.log(
            await chamber.sharesWorth(await chamber.s_userShares(user2.address))
        );
        console.log("TOKENS LEFT IN CONTRACT");
        console.log("usd", await usd.balanceOf(chamber.address));
        console.log("weth", await weth.balanceOf(chamber.address));
        console.log("matic", await ethers.provider.getBalance(chamber.address));
        console.log("wmatic", await wmatic.balanceOf(chamber.address))
        console.log("TOKENS IN UNI POSITION");
        console.log(await chamber.calculateCurrentPositionReserves());
        console.log("TOKENS IN AAVE POSITION");
        console.log("COLLATERAL TOKENS ");
        console.log(await chamber.getAUSDCTokenBalance());
        console.log("DEBT TOKENS ");
        console.log(
            await chamber.getVWMATICTokenBalance(),
            await chamber.getVWETHTokenBalance()
        );
        console.log("LTV IS");
        console.log(await chamber.currentLTV());

        console.log("TOTAL USD BALANCE");
        console.log(await chamber.currentUSDBalance());
        console.log("-----------------------------------------------------");
    });

    it("full circuit of withdrawals", async function () {
        const ownerUsdBalanceBefore = await usd.balanceOf(owner.address);
        
        await chamber.connect(owner).burn(1000 * 1000 * 1000);
        
        console.log("BALANCE AND SHARESWORTH OF OWNER are");
        console.log(await chamber.s_userShares(owner.address));
        console.log(
            await chamber.sharesWorth(await chamber.s_userShares(owner.address))
        );

        console.log("TOKENS LEFT IN CONTRACT");
        console.log("usd", await usd.balanceOf(chamber.address));
        console.log("weth", await weth.balanceOf(chamber.address));
        console.log("matic", await ethers.provider.getBalance(chamber.address));
        console.log("wmatic", await wmatic.balanceOf(chamber.address))
        console.log("TOKENS IN UNI POSITION");
        console.log(await chamber.calculateCurrentPositionReserves());
        console.log("TOKENS IN AAVE POSITION");
        console.log("COLLATERAL TOKENS ");
        console.log(await chamber.getAUSDCTokenBalance());
        console.log("DEBT TOKENS ");
        console.log(
            await chamber.getVWMATICTokenBalance(),
            await chamber.getVWETHTokenBalance()
        );
        console.log("LTV IS");
        console.log(await chamber.currentLTV());

        console.log("TOTAL USD BALANCE");
        console.log(await chamber.currentUSDBalance());
        console.log("OWNER USD BALANCE DIFFERENCE");
        console.log((await usd.balanceOf(owner.address)).sub(ownerUsdBalanceBefore))

        console.log("-----------------------------------------------------");
    })

});