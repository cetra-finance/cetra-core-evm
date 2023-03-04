const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const { networkConfig } = require("../../helper-hardhat-config");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");
const JSBI = require("jsbi");
const { keccak256 } = require("ethers/lib/utils");

describe("Basic tests sonneSNX", function () {
    let owner, _, user1, user2, donorWallet;
    let usd, weth, snx, soUSDC, soWETH, soSNX;
    let sonneOracle, UniRouter;

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
        await crv
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
                        networkConfig[network.config.chainId + 1].usdcAddress,
                        500,
                        networkConfig[network.config.chainId + 1].wmaticAddress,
                        3000,
                        networkConfig[network.config.chainId + 1].crvAddress,
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
                        networkConfig[network.config.chainId + 1].crvAddress,
                        3000,
                        networkConfig[network.config.chainId + 1].wmaticAddress,
                        500,
                        networkConfig[network.config.chainId + 1].usdcAddress,
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
        await crv
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
                        networkConfig[network.config.chainId + 1].usdcAddress,
                        500,
                        networkConfig[network.config.chainId + 1].wmaticAddress,
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
                        networkConfig[network.config.chainId + 1].wmaticAddress,
                        500,
                        networkConfig[network.config.chainId + 1].usdcAddress,
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

    const makeSwapHelper2 = async (user, amount, way) => {
        await usd.connect(user).approve(UniRouter.address, 100000000 * 1000000);
        await wmatic
            .connect(user)
            .approve(
                UniRouter.address,
                ethers.utils.parseEther("100000000000000")
            );
        await crv
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
                        networkConfig[network.config.chainId + 1].usdcAddress,
                        500,
                        networkConfig[network.config.chainId + 1].crvAddress,
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
                        networkConfig[network.config.chainId + 1].crvAddress,
                        500,
                        networkConfig[network.config.chainId + 1].usdcAddress,
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

    const makeSwapHelper3 = async (user, amount, way) => {
        await usd.connect(user).approve(UniRouter.address, 100000000 * 1000000);
        await wmatic
            .connect(user)
            .approve(
                UniRouter.address,
                ethers.utils.parseEther("100000000000000")
            );
        await crv
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
                        networkConfig[network.config.chainId + 1].wmaticAddress,
                        3000,
                        networkConfig[network.config.chainId + 1].crvAddress,
                    ]
                ),
                recipient: user.address,
                deadline:
                    (await ethers.provider.getBlock("latest")).timestamp +
                    10000,
                amountIn: ethers.utils.parseEther(amount.toString()),
                amountOutMinimum: 0,
            });
        } else {
            await UniRouter.connect(user).exactInput({
                path: ethers.utils.solidityPack(
                    ["address", "uint24", "address"],
                    [
                        networkConfig[network.config.chainId + 1].crvAddress,
                        3000,
                        networkConfig[network.config.chainId + 1].wmaticAddress,
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
            20
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
        console.log("snx:", (await snx.balanceOf(chamber.address)).toString());

        console.log(
            "Owner fees:",
            (await chamber.getAdminBalance()).toString()
        );

        console.log("TOKENS IN UNI POSITION:");
        console.log((await chamber.calculateCurrentPoolReserves()).toString());
        console.log("TOKENS IN AAVE POSITION");
        console.log(
            "COLLATERAL TOKENS ($):",
            (await soUSDC.balanceOf(chamber.address)).toString()
        );
        console.log("DEBT TOKENS:");
        console.log(
            "DEPT IN WETH:",
            (await soWETH.borrowBalanceStored(chamber.address)).toString(),
            "\nDEPT IN SNX:",
            (await soSNX.borrowBalanceStored(chamber.address)).toString()
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
        console.log(network.config.chainId);
        accounts = await ethers.getSigners();
        owner = accounts[0];
        user1 = accounts[1];
        user2 = accounts[2];
        usd = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.usdcAddress
        );
        snx = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.snxAddress
        );
        weth = await ethers.getContractAt(
            "IERC20",
            currNetworkConfig.wethAddress
        );
        soUSDC = await ethers.getContractAt(
            "ICErc20",
            currNetworkConfig.soUSDC
        );
        soSNX = await ethers.getContractAt("ICErc20", currNetworkConfig.soSNX);
        soWETH = await ethers.getContractAt(
            "ICErc20",
            currNetworkConfig.soWETH
        );
        sonneOracle = await ethers.getContractAt(
            "PriceOracle",
            currNetworkConfig.sonnePriceOracle
        );
        UniRouter = await ethers.getContractAt(
            "ISwapRouter",
            currNetworkConfig.uniswapRouterAddress
        );

        const chamberFactory = await ethers.getContractFactory(
            "ChamberV1_WETHSNX_Sonne"
        );
        chamber = await chamberFactory.deploy(
            currNetworkConfig.uniswapRouterAddress,
            currNetworkConfig.uniswapPoolAddress,
            currNetworkConfig.sonneComptrollerAddress,
            currNetworkConfig.soUSDC,
            currNetworkConfig.soWETH,
            currNetworkConfig.soSNX,
            currNetworkConfig.sonnePriceOracle,
            currNetworkConfig.ticksRange
        );
        console.log(currNetworkConfig.uniswapPoolAddress);

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
            .transfer(owner.address, 10000 * 1000 * 1000);
        await usd
            .connect(donorWallet)
            .transfer(user1.address, 10000 * 1000 * 1000);
        await usd
            .connect(donorWallet)
            .transfer(user2.address, 10000 * 1000 * 1000);

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
            .giveApprove(
                usd.address,
                currNetworkConfig.sonneComptrollerAddress
            );
        await chamber
            .connect(owner)
            .giveApprove(usd.address, currNetworkConfig.uniswapRouterAddress);
        await chamber
            .connect(owner)
            .giveApprove(usd.address, currNetworkConfig.uniswapPoolAddress);
        await chamber
            .connect(owner)
            .giveApprove(usd.address, currNetworkConfig.soUSDC);

        await chamber
            .connect(owner)
            .giveApprove(
                snx.address,
                currNetworkConfig.sonneComptrollerAddress
            );
        await chamber
            .connect(owner)
            .giveApprove(snx.address, currNetworkConfig.uniswapRouterAddress);
        await chamber
            .connect(owner)
            .giveApprove(snx.address, currNetworkConfig.uniswapPoolAddress);
        await chamber
            .connect(owner)
            .giveApprove(snx.address, currNetworkConfig.soSNX);

        await chamber
            .connect(owner)
            .giveApprove(
                weth.address,
                currNetworkConfig.sonneComptrollerAddress
            );
        await chamber
            .connect(owner)
            .giveApprove(weth.address, currNetworkConfig.uniswapRouterAddress);
        await chamber
            .connect(owner)
            .giveApprove(weth.address, currNetworkConfig.uniswapPoolAddress);
        await chamber
            .connect(owner)
            .giveApprove(weth.address, currNetworkConfig.soSNX);
    });

    describe("every user mints", async function () {
        it("owner mints sonneSNX 1000$", async function () {
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
        let WmaticUsdcPrices, CrvUsdcPrices;

        it("makes all swaps", async function () {
            console.log(
                "matic/usd",
                await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18)
            );
            console.log(
                "crv = ",
                (await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18))[0] *
                    (await getPriceFromPair(crv, wmatic, 3000, 1e18, 1e18))[1] +
                    " usd"
            );
            console.log(
                "matic/crv",
                await getPriceFromPair(crv, wmatic, 3000, 1e18, 1e18)
            );

            await wmatic
                .connect(donorWallet)
                .deposit({ value: ethers.utils.parseEther("10000000") });

            for (let i = 0; i < 10; i++) {
                await makeSwap(donorWallet, 60000, true);
                await makeSwap(donorWallet, 50000, false);
            }

            CrvUsdcPrices =
                (await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18))[0] *
                (await getPriceFromPair(crv, wmatic, 3000, 1e18, 1e18))[1];

            WmaticUsdcPrices = (
                await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18)
            )[0];

            console.log(
                "matic/usd",
                await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18)
            );
            console.log(
                "crv = ",
                (await getPriceFromPair(usd, wmatic, 500, 1e6, 1e18))[0] *
                    (await getPriceFromPair(crv, wmatic, 3000, 1e18, 1e18))[1] +
                    " usd"
            );
            console.log(
                "matic/crv",
                await getPriceFromPair(crv, wmatic, 3000, 1e18, 1e18)
            );

            mine(1000, { interval: 72 });
        });

        it("should set all oracles", async function () {
            await setNewOraclePrice(crv, Math.round(CrvUsdcPrices * 1e8));
            await setNewOraclePrice(wmatic, Math.round(WmaticUsdcPrices * 1e8));
        });
    });

    describe("checks 2", async function () {
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

    describe("checks 4", async function () {
        it("makes all checks", async function () {
            await makeAllChecks();
        });
    });
});
