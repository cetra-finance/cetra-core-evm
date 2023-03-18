const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const { networkConfig } = require("../../helper-hardhat-config");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");
const JSBI = require("jsbi");

describe("usdcEth", function () {
    let owner, _, user1, user2, donorWallet;
    let usd, weth, aUSD, vWETH;
    let aaveOracle, UniRouter;

    // =================================
    // Helper functions
    // =================================

    const makeSwap = async (user, amount, way) => {
        await usd.connect(user).approve(UniRouter.address, 100000000 * 1000000);
        await weth
            .connect(user)
            .approve(
                UniRouter.address,
                ethers.utils.parseEther("100000000000000")
            );
        if (way) {
            await UniRouter.connect(user).exactInput({
                path: ethers.utils.solidityPack(
                    ["address", "uint24", "address"],
                    [
                        networkConfig[network.config.chainId].usdcAddress,
                        500,
                        networkConfig[network.config.chainId].wethAddress,
                    ]
                ),
                recipient: user.address,
                deadline:
                    (await ethers.provider.getBlock("latest")).timestamp +
                    10000,
                amountIn: amount * 1000000,
                amountOutMinimum: 0,
            });
        } else {
            await UniRouter.connect(user).exactInput({
                path: ethers.utils.solidityPack(
                    ["address", "uint24", "address"],
                    [
                        networkConfig[network.config.chainId].wethAddress,
                        500,
                        networkConfig[network.config.chainId].usdcAddress,
                    ]
                ),
                recipient: user.address,
                deadline:
                    (await ethers.provider.getBlock("latest")).timestamp +
                    10000,
                amountIn: ethers.utils.parseEther(amount.toString()),
                amountOutMinimum: 0,
            });
        }
    };

    const setNewOraclePrice = async (asset, newPrice) => {
        await helpers.impersonateAccount(
            "0xdc9a35b16db4e126cfedc41322b3a36454b1f772"
        );
        oracleOwner = await ethers.getSigner(
            "0xdc9a35b16db4e126cfedc41322b3a36454b1f772"
        );

        await helpers.setBalance(
            oracleOwner.address,
            ethers.utils.parseEther("1000")
        );

        const OracleReplaceFactory = await ethers.getContractFactory(
            "AaveOracleReplace"
        );
        const oracleReplace = await OracleReplaceFactory.deploy(newPrice);

        await aaveOracle
            .connect(oracleOwner)
            .setAssetSources([asset.address], [oracleReplace.address]);
    };

    const getPriceFromPair = async (
        token0,
        token1,
        poolFee,
        decimals0,
        decimals1
    ) => {
        const factoryAddress = await UniRouter.factory();
        const factory = await ethers.getContractAt(
            "IUniswapV3Factory",
            factoryAddress
        );
        const poolAddress = await factory.getPool(
            token0.address,
            token1.address,
            poolFee
        );
        const pool = await ethers.getContractAt("IUniswapV3Pool", poolAddress);
        const sqrt = await pool.slot0();
        const token0Price =
            (sqrt[0] * sqrt[0] * decimals0) /
            decimals1 /
            JSBI.BigInt(2) ** JSBI.BigInt(192);
        const token1Price =
            ((JSBI.BigInt(2) ** JSBI.BigInt(192) / sqrt[0] / sqrt[0]) *
                decimals1) /
            decimals0;
        return [token0Price, token1Price];
    };

    // =================================
    // Main functions
    // =================================

    const makeDeposit = async (user, amount) => {
        // const contractBalanceBefore = await chamber.currentUSDBalance();
        // const userInnerBalanceBefore = await chamber.sharesWorth(
        //     await chamber.get_s_userShares(user.address)
        // );
        await chamber.connect(user).mint(amount);
        console.log("contract balance", await chamber.currentUSDBalance());
        // expect(await chamber.currentUSDBalance()).to.be.closeTo(
        //     contractBalanceBefore.add(amount),
        //     100000
        // );
        // expect(
        //     await chamber.sharesWorth(
        //         await chamber.get_s_userShares(user.address)
        //     )
        // ).to.be.closeTo(userInnerBalanceBefore.add(amount), 100000);
    };

    const makeBurn = async (user, amount) => {
        const userUsdBalanceBefore = await usd.balanceOf(user.address);
        await chamber.connect(user).burn(amount);
        console.log(
            "user balance diff",
            (await usd.balanceOf(user.address))
                .sub(userUsdBalanceBefore)
                .toString()
        );
    };

    const makeAllChecks = async () => {
        console.log("TOKENS LEFT IN CONTRACT");
        console.log("usd:", (await usd.balanceOf(chamber.address)).toString());
        console.log(
            "weth:",
            (await weth.balanceOf(chamber.address)).toString()
        );

        console.log(
            "Owner fees:",
            (await chamber.getAdminBalance()).toString()
        );

        console.log("TOKENS IN UNI POSITION:");
        console.log((await chamber.calculateCurrentPoolReserves()).toString());
        console.log("TOKENS IN AAVE POSITION");
        console.log(
            "COLLATERAL TOKENS ($):",
            (await aUSD.balanceOf(chamber.address)).toString()
        );
        console.log(
            "DEPT IN WETH:",
            (await vWETH.balanceOf(chamber.address)).toString()
        );
        console.log("LTV IS:", (await chamber.currentLTV()).toString());

        console.log(
            "TOTAL USD BALANCE:",
            (await chamber.currentUSDBalance()).toString()
        );

        console.log(
            "HEDGE DEVIATION:",
            (await chamber.currentHedgeDev()).toString()
        );
    };

    // =================================
    // Main tests
    // =================================

    before(async () => {
        console.log(network.config.chainId);
        console.log("DEPLOYING VAULT, FUNDING USER ACCOUNTS...");
        const currNetworkConfig = networkConfig[network.config.chainId + 4];
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
        aUSD = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.aaveAUSDCAddress
        );
        vWETH = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.aaveVWETHAddress
        );
        aaveOracle = await ethers.getContractAt(
            "IAaveOracle",
            currNetworkConfig.aaveOracleAddress
        );
        UniRouter = await ethers.getContractAt(
            "ISwapRouter",
            currNetworkConfig.uniswapRouterAddress
        );

        const chamberFactory = await ethers.getContractFactory(
            "ChamberV1Stable"
        );
        chamber = await chamberFactory.deploy(
            currNetworkConfig.uniswapRouterAddress,
            currNetworkConfig.uniswapPoolAddress,
            currNetworkConfig.aaveV3PoolAddress,
            currNetworkConfig.aaveVWETHAddress,
            currNetworkConfig.aaveOracleAddress,
            currNetworkConfig.aaveAUSDCAddress,
            currNetworkConfig.ticksRange
        );
        await chamber.setLTV(
            currNetworkConfig.targetLTV,
            currNetworkConfig.minLTV,
            currNetworkConfig.maxLTV,
            currNetworkConfig.hedgeDev
        );

        await chamber.deployed();

        await helpers.impersonateAccount(currNetworkConfig.donorWalletAddress);
        donorWallet = await ethers.getSigner(
            currNetworkConfig.donorWalletAddress
        );
        await helpers.impersonateAccount(currNetworkConfig.wethHolderAddress);
        wethHolderWallet = await ethers.getSigner(
            currNetworkConfig.wethHolderAddress
        );
        await weth
            .connect(wethHolderWallet)
            .transfer(
                donorWallet.address,
                weth.balanceOf(currNetworkConfig.wethHolderAddress)
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
            .giveApprove(weth.address, currNetworkConfig.aaveV3PoolAddress);
        await chamber
            .connect(owner)
            .giveApprove(weth.address, currNetworkConfig.uniswapPoolAddress);
    });

    describe("every user mints", async function () {
        it("owner mints 1000$", async function () {
            await makeDeposit(owner, 5 * 1e6);
        });

        it("user1 mints 1500$", async function () {
            await makeDeposit(user1, 1500 * 1e6);
        });

        it("user2 mints 2500$", async function () {
            await makeDeposit(user2, 2500 * 1e6);
        });

        it("user2 mints 2500$", async function () {
            await makeDeposit(user2, 2500 * 1e6);
        });

        it("user1 mints 1500$", async function () {
            await makeDeposit(user1, 1500 * 1e6);
        });
    });

    describe("checks 1", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("should make swaps in uni pools, so our position collect some fees", async function () {
        let WethUsdcPrices;

        it("makes all swaps", async function () {
            console.log(
                "usd/eth",
                await getPriceFromPair(usd, weth, 500, 1e6, 1e18)
            );

            for (let i = 0; i < 20; i++) {
                let balanceBefore = await weth.balanceOf(donorWallet.address);
                console.log(balanceBefore);
                await makeSwap(donorWallet, 100000, true);
                await makeSwap(
                    donorWallet,
                    ethers.utils.formatEther(
                        (await weth.balanceOf(donorWallet.address))
                            .sub(balanceBefore)
                            .sub(ethers.utils.parseEther("40"))
                    ),
                    false
                );
            }

            usdWethPrices = await getPriceFromPair(usd, weth, 500, 1e6, 1e18);

            console.log(
                "usd/weth",
                await getPriceFromPair(usd, weth, 500, 1e6, 1e18)
            );

            mine(1000, { interval: 72 });
        });

        it("should set all oracles", async function () {
            console.log(usdWethPrices);
            await setNewOraclePrice(weth, Math.round(usdWethPrices[1] * 1e8));
        });
    });

    describe("checks 2", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("checks after rebalance", async function () {
        it("owner rebalances position", async function () {
            await chamber.performUpkeep("0x");
        });
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("user mints in imbalanced pool", async function () {
        it("owner mints 1000$", async function () {
            await makeDeposit(owner, 1000 * 1e6);
        });
    });
    describe("checks addition", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("users burn all their positions", async function () {
        it("owner burns his position", async function () {
            const toBurn = await chamber.get_s_userShares(owner.address);
            await makeBurn(owner, toBurn);
        });

        it("user1 burns his position", async function () {
            const toBurn = await chamber.get_s_userShares(user1.address);
            await makeBurn(user1, toBurn);
        });

        it("user2 burns his position", async function () {
            const toBurn = await chamber.get_s_userShares(user2.address);
            await makeBurn(user2, toBurn);
        });
    });

    describe("checks 3", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("Owner withdraw fees", async function () {
        it("owner withdraws fees", async function () {
            await chamber.connect(owner)._redeemFees();
        });
    });

    describe("user mints in imbalanced pool", async function () {
        it("owner mints 1000$", async function () {
            await makeDeposit(owner, 1000 * 1e6);
        });
    });

    describe("checks 4", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });
});
