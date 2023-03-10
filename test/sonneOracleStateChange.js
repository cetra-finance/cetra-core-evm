const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

describe("Basic tests new", function () {
    let owner, _, user1, user2;
    let sonneOracle, EACAggregatorProxy;

    before(async function () {
        [owner, _, user1, user2] = await ethers.getSigners();
        sonneOracle = await ethers.getContractAt(
            "IChainlinkPriceOracle",
            "0xEFc0495DA3E48c5A55F73706b249FD49d711A502"
        );
        EACAggregatorProxy = await ethers.getContractAt(
            "EACAggregatorProxy",
            // so(any token name) - names of sonne tokens
            // soDAI, soUSDT, soOP, soUSDC, soWETH, soSUSD, soSNX
            await sonneOracle.priceFeeds("soWETH")
        );
    });

    it("should change WETHoracle states", async function () {

        let SonneOracleReplacement = await ethers.getContractFactory(
            "sonneOracleReplace"
        );
        // pass to constructor new price
        // 8 decimals
        let sonneOracleReplacement = await SonneOracleReplacement.deploy(123400000000);

        await helpers.setStorageAt(
            EACAggregatorProxy.address,
            2,
            '0x00000000000000000000' + (sonneOracleReplacement.address).toString().replace("0x", "") + "0001"
        );

    });
});
