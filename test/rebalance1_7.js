const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");
const JSBI = require("jsbi");

describe("maticToEthPriceFall", function () {
    let owner, _, user1, user2, donorWallet;
    let usd, weth, aUSD, vMATIC, vWETH;
    let aaveOracle, UniRouter;

    // =================================
    // Helper functions
    // =================================

    const makeSwap = async (user, amount, way) => {
        await usd.connect(user).approve(UniRouter.address, 100000000 * 1000000);
        await wmatic
            .connect(user)
            .approve(
                UniRouter.address,
                ethers.utils.parseEther("100000000000000")
            );

        if (way) {
            await UniRouter.connect(user).exactInput({
                path: ethers.utils.solidityPack(
                    ["address", "uint24", "address", "uint24", "address"],
                    [
                        networkConfig[network.config.chainId].usdcAddress,
                        500,
                        networkConfig[network.config.chainId].wethAddress,
                        500,
                        networkConfig[network.config.chainId].wmaticAddress,
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
                    ["address", "uint24", "address", "uint24", "address"],
                    [
                        networkConfig[network.config.chainId].wmaticAddress,
                        500,
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

    const makeSwapHelper = async (user, amount, way) => {
        await usd.connect(user).approve(UniRouter.address, 100000000 * 1000000);
        await wmatic
            .connect(user)
            .approve(
                UniRouter.address,
                ethers.utils.parseEther("100000000000000")
            );
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
                        networkConfig[network.config.chainId].wmaticAddress,
                    ]
                ),
                recipient: user.address,
                deadline:
                    (await ethers.provider.getBlock("latest")).timestamp +
                    10000,
                amountIn: amount * 1e6,
                amountOutMinimum: 0,
            });
        } else {
            await UniRouter.connect(user).exactInput({
                path: ethers.utils.solidityPack(
                    ["address", "uint24", "address"],
                    [
                        networkConfig[network.config.chainId].wmaticAddress,
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
            (sqrt[0] * sqrt[0] * decimals1) /
            decimals0 /
            JSBI.BigInt(2) ** JSBI.BigInt(192);
        const token1Price =
            ((JSBI.BigInt(2) ** JSBI.BigInt(192) / sqrt[0] / sqrt[0]) *
                decimals0) /
            decimals1;
        return [token0Price, token1Price];
    };

    // =================================
    // Main functions
    // =================================

    const makeDeposit = async (user, amount) => {
        const contractBalanceBefore = await chamber.currentUSDBalance();
        // const userInnerBalanceBefore = await chamber.sharesWorth(await chamber.get_s_userShares(user.address));
        await chamber.connect(user).mint(amount);
        expect(await chamber.currentUSDBalance()).to.be.closeTo(
            contractBalanceBefore.add(amount),
            10
        );
        // expect(await chamber.sharesWorth(await chamber.get_s_userShares(user.address))).to.be.closeTo(userInnerBalanceBefore.add(amount), 10);
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
            "matic:",
            (await ethers.provider.getBalance(chamber.address)).toString()
        );
        console.log(
            "wmatic:",
            (await wmatic.balanceOf(chamber.address)).toString()
        );

        console.log(
            "Owner fees:", (await chamber.getAdminBalance()).toString(),
        )

        console.log("TOKENS IN UNI POSITION:");
        console.log((await chamber.calculateCurrentPoolReserves()).toString());
        console.log("TOKENS IN AAVE POSITION");
        console.log(
            "COLLATERAL TOKENS ($):",
            (await aUSD.balanceOf(chamber.address)).toString()
        );
        console.log("DEBT TOKENS:");
        console.log(
            "DEPT IN MATIC:",
            (await vMATIC.balanceOf(chamber.address)).toString(),
            "\nDEPT IN WETH:",
            (await vWETH.balanceOf(chamber.address)).toString()
        );
        console.log("LTV IS:", (await chamber.currentLTV()).toString());

        console.log(
            "TOTAL USD BALANCE:",
            (await chamber.currentUSDBalance()).toString()
        );
    };

    // =================================
    // Main tests
    // =================================

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
            "WMATIC",
            currNetworkConfig.wmaticAddress
        );
        aUSD = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.aaveAUSDCAddress
        )
        vMATIC = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.aaveVWMATICAddress
        )
        vWETH = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.aaveVWETHAddress
        )
        aaveOracle = await ethers.getContractAt(
            "IAaveOracle",
            currNetworkConfig.aaveOracleAddress
        );
        UniRouter = await ethers.getContractAt(
            "ISwapRouter",
            networkConfig[network.config.chainId].uniswapRouterAddress
        );

        const chamberFactory = await ethers.getContractFactory("ChamberV1");
        chamber = await chamberFactory.deploy(
            currNetworkConfig.uniswapRouterAddress,
            currNetworkConfig.uniswapPoolAddress,
            currNetworkConfig.aaveV3PoolAddress,
            currNetworkConfig.aaveVWMATICAddress,
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
    });

    describe("every user mints | first circuit", async function () {
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

    describe("checks 1 | first circuit", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("should make swaps in uni pools, so our position collect some fees | first circuit", async function () {
        let WethWmaticPrices, WethUsdcPrices;

        it("makes all swaps", async function () {
            console.log(
                "matic/usd",
                await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18)
            );
            console.log(
                "usd/weth",
                await getPriceFromPair(weth, usd, 500, 1e18, 1e6)
            );
            console.log(
                "matic/weth",
                await getPriceFromPair(weth, wmatic, 500, 1e18, 1e18)
            );

            await wmatic
                .connect(donorWallet)
                .deposit({ value: ethers.utils.parseEther("1000000") });

            for (let i = 0; i < 20; i++) {
                let balanceBefore = await wmatic.balanceOf(donorWallet.address);
                await makeSwap(donorWallet, 100000, true);
                await makeSwap(
                    donorWallet,
                    ethers.utils.formatEther(
                        (
                            await wmatic.balanceOf(donorWallet.address)
                        ).sub(balanceBefore)
                    ),
                    false
                );
            }

            WethWmaticPrices = await getPriceFromPair(
                weth,
                wmatic,
                500,
                1e18,
                1e18
            );
            WethUsdcPrices = await getPriceFromPair(weth, usd, 500, 1e18, 1e6);
            const wmaticTargetPrice =
                Math.round((WethUsdcPrices[1] / WethWmaticPrices[1]) * 1e8) *
                1e10;

            if (
                (await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18))[0] *
                    1e18 <
                BigNumber.from(wmaticTargetPrice.toString())
            ) {
                while (
                    (await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18))[0] *
                        1e18 <
                    BigNumber.from(wmaticTargetPrice.toString())
                ) {
                    makeSwapHelper(donorWallet, 5000, true);
                }
            } else {
                while (
                    (await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18))[0] *
                        1e18 >
                    BigNumber.from(wmaticTargetPrice.toString())
                ) {
                    makeSwapHelper(donorWallet, 4000, false);
                }
            }

            console.log(
                "matic/usd",
                await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18)
            );
            console.log(
                "usd/weth",
                await getPriceFromPair(weth, usd, 500, 1e18, 1e6)
            );
            console.log(
                "matic/weth",
                await getPriceFromPair(weth, wmatic, 500, 1e18, 1e18)
            );

            mine(1000, { interval: 72 });
        });

        it("should set all oracles", async function () {
            await setNewOraclePrice(weth, Math.round(WethUsdcPrices[1] * 1e8));
            await setNewOraclePrice(
                wmatic,
                Math.round((WethUsdcPrices[1] / WethWmaticPrices[1]) * 1e8)
            );
        });
    });

    describe("checks 2 | first circuit", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("users burn all their positions | first circuit", async function () {
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

    describe("checks 3 | first circuit", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("Owner withdraw fees | first circuit", async function () {
        it("owner withdraws fees", async function () {
            await chamber.connect(owner)._redeemFees();
        })
    })

    describe("checks 4 | first circuit", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("every user mints | second circuit", async function () {
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

    describe("checks 1 | second circuit", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("should make swaps in uni pools, so our position collect some fees | second circuit", async function () {
        let WethWmaticPrices, WethUsdcPrices;

        it("makes all swaps", async function () {
            console.log(
                "matic/usd",
                await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18)
            );
            console.log(
                "usd/weth",
                await getPriceFromPair(weth, usd, 500, 1e18, 1e6)
            );
            console.log(
                "matic/weth",
                await getPriceFromPair(weth, wmatic, 500, 1e18, 1e18)
            );

            await wmatic
                .connect(donorWallet)
                .deposit({ value: ethers.utils.parseEther("1000000") });

            for (let i = 0; i < 20; i++) {
                let balanceBefore = await wmatic.balanceOf(donorWallet.address);
                await makeSwap(donorWallet, 100000, true);
                await makeSwap(
                    donorWallet,
                    ethers.utils.formatEther(
                        (
                            await wmatic.balanceOf(donorWallet.address)
                        ).sub(balanceBefore)
                    ),
                    false
                );
            }

            WethWmaticPrices = await getPriceFromPair(
                weth,
                wmatic,
                500,
                1e18,
                1e18
            );
            WethUsdcPrices = await getPriceFromPair(weth, usd, 500, 1e18, 1e6);
            const wmaticTargetPrice =
                Math.round((WethUsdcPrices[1] / WethWmaticPrices[1]) * 1e8) *
                1e10;

            if (
                (await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18))[0] *
                    1e18 <
                BigNumber.from(wmaticTargetPrice.toString())
            ) {
                while (
                    (await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18))[0] *
                        1e18 <
                    BigNumber.from(wmaticTargetPrice.toString())
                ) {
                    makeSwapHelper(donorWallet, 5000, true);
                }
            } else {
                while (
                    (await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18))[0] *
                        1e18 >
                    BigNumber.from(wmaticTargetPrice.toString())
                ) {
                    makeSwapHelper(donorWallet, 4000, false);
                }
            }

            console.log(
                "matic/usd",
                await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18)
            );
            console.log(
                "usd/weth",
                await getPriceFromPair(weth, usd, 500, 1e18, 1e6)
            );
            console.log(
                "matic/weth",
                await getPriceFromPair(weth, wmatic, 500, 1e18, 1e18)
            );

            mine(1000, { interval: 72 });
        });

        it("should set all oracles | second circuit", async function () {
            await setNewOraclePrice(weth, Math.round(WethUsdcPrices[1] * 1e8));
            await setNewOraclePrice(
                wmatic,
                Math.round((WethUsdcPrices[1] / WethWmaticPrices[1]) * 1e8)
            );
        });
    });

    describe("checks 2 | second circuit", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("users burn all their positions | second circuit", async function () {
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

    describe("checks 3 | second circuit", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });

    describe("Owner withdraw fees | second circuit", async function () {
        it("owner withdraws fees", async function () {
            await chamber.connect(owner)._redeemFees();
        })
    })

    describe("checks 4 | second circuit", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });
});
