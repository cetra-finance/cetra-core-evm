const { ethers } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const fs = require("fs");
const { isBigIntLiteral } = require("typescript");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

async function enterChamber() {
    const currNetworkConfig = networkConfig[network.config.chainId];
    let chamber = await ethers.getContractAt(
        "ChamberV1VolStable",
        "0x93e3b2e1e3837622156fecdc6e5472af31fe10bb"
    );
    console.log(await chamber.currentUSDBalance());
    let aavePool = await ethers.getContractAt(
        "IPool",
        currNetworkConfig.aaveV3PoolAddress
    );
    let aaveOracle = await ethers.getContractAt(
        "IAaveOracle",
        currNetworkConfig.aaveOracleAddress
    );
    let WETH = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.wethAddress
    );
    let USDC = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.usdcAddress
    );
    let vWETH = await ethers.getContractAt(
        "IVariableDebtToken",
        currNetworkConfig.aaveVWETHAddress
    );
    let aUSDC = await ethers.getContractAt(
        "IAToken",
        currNetworkConfig.aaveAUSDCAddress
    );
    let uniPool = await ethers.getContractAt(
        "IUniswapV3Pool",
        currNetworkConfig.uniswapPoolAddress
    );
    
    let tokenAmts = await chamber.calculateCurrentPoolReserves();
    let aUSDAmt = BigInt(await aUSDC.balanceOf(chamber.address));
    let vWETHAmt =
        (BigInt(await vWETH.scaledBalanceOf(chamber.address)) *
            BigInt(
                await aavePool.getReserveNormalizedVariableDebt(WETH.address)
            )) /
        BigInt(10) ** BigInt(27);

    let respFromStorage = await helpers.getStorageAt(chamber.address, 3)
    let lowerTick = (parseInt(("0x" + respFromStorage.slice(60, 66)), 16) - parseInt("0x1000000", 16))
    let upperTick = (parseInt(("0x" + respFromStorage.slice(54, 60)), 16) - parseInt("0x1000000", 16))

    let position = await uniPool.positions(
        ethers.utils.keccak256(
            ethers.utils.solidityPack(
                ["address", "int24", "int24"],
                [
                    chamber.address,
                    lowerTick,
                    upperTick
                ]
            )
        )
    )

    const computeFee = async (isZero, feeGrowthInsideLast, liquidity) => {
        let feeGrowthOutsideLower
        let feeGrowthOutsideUpper
        let feeGrowthGlobal
        if (isZero) {
            feeGrowthGlobal = await uniPool.feeGrowthGlobal0X128()
            feeGrowthOutsideLower = (await uniPool.ticks(lowerTick)).feeGrowthOutside0X128
            feeGrowthOutsideUpper = (await uniPool.ticks(upperTick)).feeGrowthOutside0X128
        } else {
            feeGrowthGlobal = await uniPool.feeGrowthGlobal1X128()
            feeGrowthOutsideLower = (await uniPool.ticks(lowerTick)).feeGrowthOutside1X128
            feeGrowthOutsideUpper = (await uniPool.ticks(upperTick)).feeGrowthOutside1X128
        }

        let feeGrowthInside = feeGrowthGlobal - feeGrowthOutsideLower - feeGrowthOutsideUpper;

        return (BigInt(liquidity) * (BigInt(feeGrowthInside) - BigInt(feeGrowthInsideLast))) / BigInt(0x100000000000000000000000000000000)
    }

    let fee0 = await computeFee(true, position.feeGrowthInside0LastX128, position._liquidity)
    let fee1 = await computeFee(false, position.feeGrowthInside1LastX128, position._liquidity)

    console.log('fees', fee0, fee1)

    let usdcPrice = BigInt(await aaveOracle.getAssetPrice(USDC.address));
    let wethPrice = BigInt(await aaveOracle.getAssetPrice(WETH.address));
    console.log(
        aUSDAmt +
            BigInt(tokenAmts[1]) +
            ((BigInt(tokenAmts[0]) - vWETHAmt) *
                wethPrice *
                BigInt(10) ** BigInt(6)) /
                BigInt(10) ** BigInt(18) /
                usdcPrice
    );
    console.log(
        await USDC.balanceOf(chamber.address),
        await WETH.balanceOf(chamber.address)
    );
    console.log(BigInt(tokenAmts[0]), BigInt(tokenAmts[1]), aUSDAmt, vWETHAmt);

    // console.log(tx1R, tx2R);
}

enterChamber()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
