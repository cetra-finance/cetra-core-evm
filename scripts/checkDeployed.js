const { ethers } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const fs = require("fs");
const { isBigIntLiteral } = require("typescript");

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
    let tokenAmts = await chamber.calculateCurrentPoolReserves();
    let aUSDAmt = BigInt(await aUSDC.balanceOf(chamber.address));
    let vWETHAmt =
        (BigInt(await vWETH.scaledBalanceOf(chamber.address)) *
            BigInt(
                await aavePool.getReserveNormalizedVariableDebt(WETH.address)
            )) /
        BigInt(10) ** BigInt(27);
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
