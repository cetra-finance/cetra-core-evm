const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");
const JSBI = require("jsbi");

describe("Basic tests new", function () {
    let owner, _, user1, user2, donorWallet;
    let usd, weth;
    let aaveOracle, UniRouter;

    const makeSwap = async(user, amount, way) => {
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

    const makeSwapHelper = async(user, amount, way) => {
        await usd.connect(user).approve(UniRouter.address, 100000000 * 1000000);
        await wmatic.connect(user).approve(UniRouter.address,  ethers.utils.parseEther("100000000000000"));
        await weth.connect(user).approve(UniRouter.address,  ethers.utils.parseEther("100000000000000"));

        if (way) {
            await UniRouter.connect(user).exactInput(
                {
                    path: ethers.utils.solidityPack(["address", "uint24", "address"], [networkConfig[network.config.chainId].usdcAddress, 500, networkConfig[network.config.chainId].wmaticAddress]),
                    recipient: user.address,
                    deadline: (await ethers.provider.getBlock("latest")).timestamp + 10000,
                    amountIn: amount * 1e6,
                    amountOutMinimum: 0
                },
            )
        } else {
            await UniRouter.connect(user).exactInput(
                {
                    path: ethers.utils.solidityPack(["address", "uint24", "address"], [networkConfig[network.config.chainId].wethAddress, 500, networkConfig[network.config.chainId].usdcAddress]),
                    recipient: user.address,
                    deadline: (await ethers.provider.getBlock("latest")).timestamp + 10000,
                    amountIn: ethers.utils.parseEther(amount.toString()),
                    amountOutMinimum: 0
                },
            )
        }

    }

    const setNewOraclePrice = async (asset, newPrice) => {
        await helpers.impersonateAccount("0xdc9a35b16db4e126cfedc41322b3a36454b1f772");
        oracleOwner = await ethers.getSigner(
            "0xdc9a35b16db4e126cfedc41322b3a36454b1f772"
        );

        await helpers.setBalance(oracleOwner.address, ethers.utils.parseEther("1000"));

        const OracleReplaceFactory = await ethers.getContractFactory("AaveOracleReplace");
        const oracleReplace = await OracleReplaceFactory.deploy(
            newPrice
        );

        await aaveOracle.connect(oracleOwner).setAssetSources([asset.address], [oracleReplace.address]);
    }

    const getPriceFromPair = async(token0, token1, poolFee, decimals0, decimals1) => {
        const factoryAddress = await UniRouter.factory();
        const factory = await ethers.getContractAt("IUniswapV3Factory", factoryAddress);
        const poolAddress = await factory.getPool(token0.address, token1.address, poolFee);
        const pool = await ethers.getContractAt("IUniswapV3Pool", poolAddress);
        const sqrt = await pool.slot0();
        const token0Price = sqrt[0] * sqrt[0] * (decimals1) / (decimals0) / JSBI.BigInt(2) ** (JSBI.BigInt(192));
        const token1Price = JSBI.BigInt(2) ** (JSBI.BigInt(192)) / sqrt[0] / sqrt[0] * (decimals0) / (decimals1);
        return [token0Price, token1Price];
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
        aaveOracle = await ethers.getContractAt(
            "IAaveOracle",
            currNetworkConfig.aaveOracleAddress
        );
        UniRouter = await ethers.getContractAt("ISwapRouter", networkConfig[network.config.chainId].uniswapRouterAddress)

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

        for (let i = 0; i < 40; i++) {
            await makeSwap(donorWallet, 100000, true);
            await makeSwap(donorWallet, 70000, false);
        }
        makeSwapHelper(donorWallet, 1568000, true);
        console.log(await getPriceFromPair(weth, usd, 500, 1e18, 1e6));
        console.log(await getPriceFromPair(wmatic, usd, 500, 1e18, 1e6));
        console.log(await getPriceFromPair(weth, wmatic, 500, 1e18, 1e18));
        console.log(await chamber.calculateCurrentPoolReserves())
        mine(1000, { interval: 72 });

        const WethWmaticPrices = await getPriceFromPair(weth, wmatic, 500, 1e18, 1e18);
        const WethUsdcPrices = await getPriceFromPair(weth, usd, 500, 1e18, 1e6);
        await setNewOraclePrice(weth, Math.round(WethUsdcPrices[1] * 1e8))
        await setNewOraclePrice(wmatic, Math.round(WethUsdcPrices[1] / WethWmaticPrices[1] * 1e8))

        console.log(await chamber.getUsdcOraclePrice())
        console.log(await chamber.getWmaticOraclePrice())
        console.log(await chamber.getWethOraclePrice())

        console.log("TOTAL USD BALANCE");
        console.log(await chamber.currentUSDBalance());
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