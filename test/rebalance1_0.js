const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");


describe("Basic tests", function () {
    let owner, _, user1, user2, user3;
    let ourRebalance, usd, weth, aWeth, aUsd, uniRouter, uniPool, aavePool, uniPositionManager;

    before(async () => {
        [owner, _, user1, user2, user3] = await ethers.getSigners();

        usd = await ethers.getContractAt("ERC20", '0x7F5c764cBc14f9669B88837ca1490cCa17c31607');
        weth = await ethers.getContractAt("ERC20", '0x4200000000000000000000000000000000000006');
        aWeth = await ethers.getContractAt("ERC20", '0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351');
        aUsd = await ethers.getContractAt("ERC20", '0x625E7708f30cA75bfd92586e17077590C60eb4cD');
        uniPositionManager = await ethers.getContractAt("INonfungiblePositionManager", '0xC36442b4a4522E871399CD717aBDD847Ab11FE88')
        aavePool = await ethers.getContractAt("IPool", '0x794a61358D6845594F94dc1DB02A252b5b4814aD');



        const OurRebalance = await ethers.getContractFactory("Rebalance1");
        ourRebalance = await OurRebalance.deploy(
            '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
            '0x4200000000000000000000000000000000000006',
            '0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45',
            '0x85149247691df622eaF1a8Bd0CaFd40BC45154a9',
            '0x76D3030728e52DEB8848d5613aBaDE88441cbc59',
            '0x794a61358D6845594F94dc1DB02A252b5b4814aD',
            '0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351',
            '0xC36442b4a4522E871399CD717aBDD847Ab11FE88'
        );
        await ourRebalance.deployed();

        await helpers.impersonateAccount("0xebe80f029b1c02862b9e8a70a7e5317c06f62cae");
        let donorWallet = await ethers.getSigner("0xebe80f029b1c02862b9e8a70a7e5317c06f62cae")

        await helpers.impersonateAccount("0xBA12222222228d8Ba445958a75a0704d566BF2C8");
        let donorWallet2 = await ethers.getSigner("0xBA12222222228d8Ba445958a75a0704d566BF2C8")

        await weth.connect(donorWallet2).transfer(owner.address, BigNumber.from("10000000000000000000"), { gasLimit: 1000000 });
        await usd.connect(donorWallet).transfer(owner.address, 10000000000);
        console.log("owner balance", await usd.balanceOf(owner.address))
        await usd.connect(donorWallet).transfer(user1.address, 10000000000);
        console.log("user1 balance", await usd.balanceOf(user1.address))
        await usd.connect(donorWallet).transfer(user2.address, 10000000000);
        console.log("user2 balance", await usd.balanceOf(user2.address))

        await usd.connect(owner).approve(ourRebalance.address, 1000000000000000);
        await usd.connect(user1).approve(ourRebalance.address, 1000000000000000);
        await usd.connect(user2).approve(ourRebalance.address, 1000000000000000);
        await weth.connect(owner).approve(ourRebalance.address, BigNumber.from("10000000000000000000000"));

        await ourRebalance.connect(owner).giveAllApproves();

        console.log(owner.address);
    });
    

    it("add liquidity test", async function () {

        await ourRebalance.connect(owner).addLiqudityToOurPosition(1000000000);
        console.log("---------------------")
        console.log(await usd.balanceOf(ourRebalance.address))
        console.log(await weth.balanceOf(ourRebalance.address))
        console.log("---------------------")

        console.log(await ourRebalance.calculateBalanceBetweenTokensForRebalance(100000))
        console.log(await usd.balanceOf(ourRebalance.address))

        await ourRebalance.connect(user1).addLiqudityToOurPosition(2000000000);
        console.log("---------------------")
        console.log(await usd.balanceOf(ourRebalance.address))
        console.log(await weth.balanceOf(ourRebalance.address))
        console.log("---------------------")
        await ourRebalance.connect(user1).addLiqudityToOurPosition(1700000000);
        console.log("---------------------")
        console.log(await usd.balanceOf(ourRebalance.address))
        console.log(await weth.balanceOf(ourRebalance.address))
        console.log("---------------------")
        await ourRebalance.connect(user2).addLiqudityToOurPosition(2500000000);
        console.log("---------------------")
        console.log(await usd.balanceOf(ourRebalance.address))
        console.log(await weth.balanceOf(ourRebalance.address))
        console.log("---------------------")
        await ourRebalance.connect(user2).addLiqudityToOurPosition(2500000000);

        console.log("owner balance", await usd.balanceOf(owner.address))
        console.log("user1 balance", await usd.balanceOf(user1.address))
        console.log("user2 balance", await usd.balanceOf(user2.address))

        let pisitionId = await ourRebalance.liquididtyTokenId();
        let position = await uniPositionManager.positions(pisitionId);
        console.log(position);
        console.log(await aavePool.getUserAccountData(ourRebalance.address));

        console.log(await ourRebalance.totalSupply())
        console.log(await ourRebalance.balanceOf(owner.address))
        console.log(await ourRebalance.sharesWorth(await ourRebalance.balanceOf(owner.address)))
        console.log(await ourRebalance.balanceOf(user1.address))
        console.log(await ourRebalance.sharesWorth(await ourRebalance.balanceOf(user1.address)))
        console.log(await ourRebalance.balanceOf(user2.address))
        console.log(await ourRebalance.sharesWorth(await ourRebalance.balanceOf(user2.address)))
        console.log("---------------------")
        console.log(await usd.balanceOf(ourRebalance.address))
        console.log(await weth.balanceOf(ourRebalance.address))
        console.log("---------------------")

    });

    it("withdraw Liqudity test", async function () {

        console.log("user1 balance", await usd.balanceOf(user1.address))
        await ourRebalance.connect(user1).withdrawLiqudityFromOurPosition(3700000000);
        console.log(await ourRebalance.balanceOf(user1.address))
        console.log(await ourRebalance.sharesWorth(await ourRebalance.balanceOf(user1.address)))
        console.log(await usd.balanceOf(ourRebalance.address))
        console.log(await weth.balanceOf(ourRebalance.address))
        console.log("user1 balance", await usd.balanceOf(user1.address))
        console.log("---------------------")
        console.log("user2 balance", await usd.balanceOf(user2.address))
        await ourRebalance.connect(user2).withdrawLiqudityFromOurPosition(5000000000);
        console.log("user2 balance", await usd.balanceOf(user2.address))
        console.log("---------------------")
        console.log("owner balance", await usd.balanceOf(owner.address))
        await ourRebalance.connect(owner).withdrawLiqudityFromOurPosition(1000000000);
        console.log("owner balance", await usd.balanceOf(owner.address))
        console.log("---------------------")
        let pisitionId = await ourRebalance.liquididtyTokenId();
        console.log(await uniPositionManager.positions(pisitionId));
        console.log(await aavePool.getUserAccountData(ourRebalance.address));
    })

    it("rebalance test", async function () {

    })

})
