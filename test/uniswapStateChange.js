const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");
const JSBI = require("jsbi");

const newTick = -7122;
const newFeeGrowthGlobal0X128 = 63;
const newFeeGrowthGlobal1X128 = 61;

describe("Basic tests new", function () {
    let owner, _, user1, user2, donorWallet;
    let UniRouter, UniPool

    const HexToSignedInt = (num, numSize) => {
        var val = {
            mask: 0x8 * Math.pow(16, numSize-1), //  0x8000 if numSize = 4
            sub: -0x1 * Math.pow(16, numSize)    //-0x10000 if numSize = 4
        }
        if((parseInt(num, 16) & val.mask) > 0) { //negative
            return (val.sub + parseInt(num, 16))
        }else {                                 //positive
            return (parseInt(num,16))
        }
     }

    before(async function () {
        [owner, _, user1, user2, donorWallet] = await ethers.getSigners();
        UniRouter = await ethers.getContractAt(
            "ISwapRouter",
            networkConfig[network.config.chainId].uniswapRouterAddress
        );
        UniPool = await ethers.getContractAt(
            "IUniswapV3Pool",
            networkConfig[network.config.chainId].uniswapPoolAddress
        );
    });

    it("should chande slot0 states", async function () {
        const prevSlot0Hex = await helpers.getStorageAt(UniPool.address, 0);
        let newTickHex = ethers.utils.hexlify(parseInt("0x9B000000", 16) + newTick)
        newTickHex = newTickHex.replace("0x", "00")

        await helpers.setStorageAt(UniPool.address, 0, (prevSlot0Hex.slice(0, 16) + newTickHex + prevSlot0Hex.slice(26, 66)));
        console.log("slot0", await UniPool.slot0())
    })

    it("should change fee states", async function () {
        let newHexFeeGrowthGlobal0X128 = ethers.utils.hexlify(newFeeGrowthGlobal0X128)
        let zero0 = 66 - newHexFeeGrowthGlobal0X128.length
        newHexFeeGrowthGlobal0X128 = "0x" + "0".repeat(zero0) + newHexFeeGrowthGlobal0X128.slice(2)
        
        let newHexFeeGrowthGlobal1X128 = ethers.utils.hexlify(newFeeGrowthGlobal1X128)
        let zero1 = 66 - newHexFeeGrowthGlobal1X128.length
        newHexFeeGrowthGlobal1X128 = "0x" + "0".repeat(zero1) + newHexFeeGrowthGlobal1X128.slice(2)

        await helpers.setStorageAt(UniPool.address, 1, newHexFeeGrowthGlobal0X128);
        await helpers.setStorageAt(UniPool.address, 2, newHexFeeGrowthGlobal1X128);

        console.log("feeGrowthGlobal0X128", await UniPool.feeGrowthGlobal0X128())
        console.log("feeGrowthGlobal1X128", await UniPool.feeGrowthGlobal1X128())
    })

})