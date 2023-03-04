const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const { networkConfig } = require("../../helper-hardhat-config");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");
const JSBI = require("jsbi");

describe("ethUsdc", function () {
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

    // =================================
    // Main functions
    // =================================

    const makeDeposit = async (user, amount) => {
        await chamber.connect(user).mint(amount);
        console.log("contract balance", await chamber.currentUSDBalance());
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
            "ChamberV1VolStable"
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
        console.log(await usd.balanceOf(donorWallet.address));

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
            .giveApprove(weth.address, currNetworkConfig.uniswapRouterAddress);
        await chamber
            .connect(owner)
            .giveApprove(weth.address, currNetworkConfig.uniswapPoolAddress);
        console.log(await usd.balanceOf(owner.address));
        console.log(await usd.balanceOf(user1.address));
        console.log(await usd.balanceOf(user2.address));
    });

    describe("every user mints", async function () {
        it("owner mints 1000$", async function () {
            await makeDeposit(owner, 1000 * 1e6);
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
