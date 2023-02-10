const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

describe("Basic tests new", function () {
    let owner, _, user1, user2, donorWallet;
    let usd, weth;

    const makeSwap = async(user, amount, way) => {
        UniRouter = await ethers.getContractAt("ISwapRouter", networkConfig[network.config.chainId].uniswapRouterAddress)
        await usd.connect(user).approve(UniRouter.address, 100000000 * 1000000);
        await wmatic.connect(user).approve(UniRouter.address,  ethers.utils.parseEther("100000000000000"));

        if (way) {
            await UniRouter.connect(user).exactInput(
                {
                    path: ethers.utils.solidityPack(["address", "uint24", "address", "uint24", "address"], [networkConfig[network.config.chainId].usdcAddress, 500, networkConfig[network.config.chainId].wethAddress, 500, networkConfig[network.config.chainId].wmaticAddress]),
                    recipient: user.address,
                    deadline: (await ethers.provider.getBlock("latest")).timestamp + 10000,
                    amountIn: amount * 1000000,
                    amountOutMinimum: 0
                },
            )
        } else {
            await UniRouter.connect(user).exactInput(
                {
                    path: ethers.utils.solidityPack(["address", "uint24", "address", "uint24", "address"], [networkConfig[network.config.chainId].wmaticAddress, 500, networkConfig[network.config.chainId].wethAddress, 500, networkConfig[network.config.chainId].usdcAddress]),
                    recipient: user.address,
                    deadline: (await ethers.provider.getBlock("latest")).timestamp + 10000,
                    amountIn: ethers.utils.parseEther(amount.toString()),
                    amountOutMinimum: 0
                },
            )
        }

    }


    before(async () => {
        console.log("DEPLOYING VAULT, FUNDING USER ACCOUNTS...");
        const currNetworkConfig = networkConfig[network.config.chainId];
        accounts = await ethers.getSigners();
        owner = accounts[0];
        user1 = accounts[1];
        user2 = accounts[2];
        usd = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.usdcAddress
        );
        weth = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.wethAddress
        );
        wmatic = await ethers.getContractAt(
            "IERC20",
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
        donorWallet = await ethers.getSigner(
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

        await chamber
            .connect(owner)
            .giveApprove(usd.address, currNetworkConfig.aaveV3PoolAddress);
        await chamber
            .connect(owner)
            .giveApprove(usd.address, currNetworkConfig.uniswapRouterAddress);
        await chamber
            .connect(owner)
            .giveApprove(usd.address, currNetworkConfig.uniswapPoolAddress);
        await chamber
            .connect(owner)
            .giveApprove(usd.address, currNetworkConfig.aaveVWETHAddress);

        await chamber
            .connect(owner)
            .giveApprove(weth.address, currNetworkConfig.aaveV3PoolAddress);
        await chamber
            .connect(owner)
            .giveApprove(weth.address, currNetworkConfig.uniswapRouterAddress);
        await chamber
            .connect(owner)
            .giveApprove(weth.address, currNetworkConfig.uniswapPoolAddress);
        await chamber
            .connect(owner)
            .giveApprove(weth.address, currNetworkConfig.aaveVWETHAddress);

        await chamber
            .connect(owner)
            .giveApprove(wmatic.address, currNetworkConfig.aaveV3PoolAddress);
        await chamber
            .connect(owner)
            .giveApprove(
                wmatic.address,
                currNetworkConfig.uniswapRouterAddress
            );

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
        console.log(await chamber.calculateCurrentPoolReserves());

        console.log("DEBT TOKENS ");
        console.log(
            await chamber.getVWMATICTokenBalance(),
            await chamber.getVWETHTokenBalance()
        );
        console.log("TOTAL USD BALANCE");
        console.log(await chamber.currentUSDBalance());

        console.log("USER1 DEPOSITS 1500$");
        await chamber.connect(user1).mint(1500 * 1000 * 1000);
        console.log("LTV IS");
        console.log(await chamber.currentLTV());
        console.log("IN POOL");
        console.log(await chamber.calculateCurrentPoolReserves());

        console.log("DEBT TOKENS ");
        console.log(
            await chamber.getVWMATICTokenBalance(),
            await chamber.getVWETHTokenBalance()
        );
        console.log("TOTAL USD BALANCE");
        console.log(await chamber.currentUSDBalance());

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
        console.log("wmatic", await wmatic.balanceOf(chamber.address));
        console.log("TOKENS IN UNI POSITION");
        console.log(await chamber.calculateCurrentPoolReserves());
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
        console.log(await chamber.calculateCurrentPoolReserves());

        for (let i = 0; i < 40; i++) {
            await makeSwap(donorWallet, 100000, true);
            await makeSwap(donorWallet, 70000, false);
        }
        mine(1000, { interval: 72 });

        console.log("TOTAL USD BALANCE");
        console.log(await chamber.currentUSDBalance());
        console.log(await chamber.calculateCurrentPoolReserves());
        console.log("-----------------------------------------------------");
    });

    it("full circuit of withdrawals", async function () {
        const ownerUsdBalanceBefore = await usd.balanceOf(owner.address);
        await chamber
            .connect(owner)
            .burn(await chamber.s_userShares(owner.address));
        console.log(
            "owner balance diff",
            (await usd.balanceOf(owner.address)).sub(ownerUsdBalanceBefore)
        );

        const user1UsdBalanceBefore = await usd.balanceOf(user1.address);

        await chamber
            .connect(user1)
            .burn(await chamber.s_userShares(user1.address));
        console.log(
            "user1 balance diff",
            (await usd.balanceOf(user1.address)).sub(user1UsdBalanceBefore)
        );

        const user2UsdBalanceBefore = await usd.balanceOf(user2.address);
        await chamber
            .connect(user2)
            .burn(await chamber.s_userShares(user2.address));
        console.log(
            "user2 balance diff",
            (await usd.balanceOf(user2.address)).sub(user2UsdBalanceBefore)
        );

        console.log("TOKENS LEFT IN CONTRACT");
        console.log("usd", await usd.balanceOf(chamber.address));
        console.log("weth", await weth.balanceOf(chamber.address));
        console.log("matic", await ethers.provider.getBalance(chamber.address));
        console.log("wmatic", await wmatic.balanceOf(chamber.address));

        console.log("TOKENS IN UNI POSITION");
        console.log(await chamber.calculateCurrentPoolReserves());
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
        console.log((await chamber.currentUSDBalance()).toString());

        console.log("-----------------------------------------------------");
    });
});
