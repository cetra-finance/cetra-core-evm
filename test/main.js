const { expect, assert } = require("chai");
const { BigNumber, utils } = require("ethers");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");


describe("Basic tests", function () {
    let owner, _, user1, user2, user3;
    let ourRebalance, usd, weth, aWeth, aUsd, uniRouter, uniPool, uniPositionManager;

    before(async () => {
        [owner, _, user1, user2, user3] = await ethers.getSigners();

        usd = await ethers.getContractAt("ERC20", '0x7F5c764cBc14f9669B88837ca1490cCa17c31607');
        weth = await ethers.getContractAt("ERC20", '0x4200000000000000000000000000000000000006');
        aWeth = await ethers.getContractAt("ERC20", '0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351');
        aUsd = await ethers.getContractAt("ERC20", '0x625E7708f30cA75bfd92586e17077590C60eb4cD');
        uniPositionManager = await ethers.getContractAt("INonfungiblePositionManager", '0xC36442b4a4522E871399CD717aBDD847Ab11FE88')



        const OurRebalance = await ethers.getContractFactory("FirstRebalanceTry");
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

        await helpers.impersonateAccount("0x35A807F9dD68C7B03A992477F85cF5a08Ee9a69e");
        let donorWallet2 = await ethers.getSigner("0x35A807F9dD68C7B03A992477F85cF5a08Ee9a69e")

        await weth.connect(donorWallet2).transfer(owner.address, BigNumber.from("10000000000000000000"));
        await usd.connect(donorWallet).transfer(owner.address, 1000000000000);
        await usd.connect(owner).approve(ourRebalance.address, 1000000000000000);
        await weth.connect(owner).approve(ourRebalance.address, BigNumber.from("10000000000000000000000"));

        await ourRebalance.connect(owner).giveAllApproves();

        console.log(owner.address);
    });
    
    // it("swap test", async function () { 
    //     // console.log(await ourRebalance.getSqrt())

    //     // console.log(await usd.balanceOf(owner.address));
    //     // console.log(await weth.balanceOf(ourRebalance.address));
    //     await ourRebalance.connect(owner).makeSwap();
    //     // console.log(await usd.balanceOf(owner.address));
    //     // console.log(await weth.balanceOf(ourRebalance.address));
    // })

    // it("aave borrow test", async function () {
    //     // console.log(await usd.balanceOf(owner.address));
    //     balanceBefore = await ethers.provider.getBalance(ourRebalance.address);
    //     console.log(await ethers.provider.getBalance(ourRebalance.address));

    //     let tx1 = await ourRebalance.connect(owner).depositToAvee();
    //     tx1.wait();
    //     // console.log("done")
    //     console.log(await aUsd.balanceOf(ourRebalance.address));
    //     console.log(await aWeth.balanceOf(owner.address));
    //     console.log(await usd.balanceOf(owner.address));
    //     console.log(await weth.balanceOf(ourRebalance.address));
    //     let tx2 = await ourRebalance.connect(owner).borrowFromAave();
    //     tx2.wait();

    //     console.log(await usd.balanceOf(owner.address));
    //     console.log(await weth.balanceOf(ourRebalance.address));

    //     console.log(await ethers.provider.getBalance(ourRebalance.address));
    //     let gas2 = tx2.gasPrice.mul(tx2.gasLimit);
    //     let gas1 = tx1.gasPrice.mul(tx1.gasLimit);
    //     expect(await ethers.provider.getBalance(ourRebalance.address)).to.be.equal(balanceBefore.add(BigNumber.from("1000000000000000000")));
    // })

    // it("provide liquidity to uni", async function () {

    //     let tick = await ourRebalance.getTick();
    //     console.log(tick);

    //     tx = await ourRebalance.connect(owner).addLuquidityToUniswap({value: BigNumber.from("2000000000000000000")});

    //     expect(await uniPositionManager.balanceOf(ourRebalance.address)).to.be.equal(1);

    //     let pisitionId = await ourRebalance.liquididtyTokenId();
    //     let position = await uniPositionManager.positions(pisitionId);
    //     console.log(position);

    //     let myPosition = await uniPositionManager.positions(293788);
    //     console.log(myPosition);
    // })

    it("full circuit test", async function () {

        // console.log(await ourRebalance.getPriceUSD(1000000000))

        await ourRebalance.connect(owner).fullCircle(1000000000);

        // let pisitionId = await ourRebalance.liquididtyTokenId();
        // let position = await uniPositionManager.positions(pisitionId);
        // console.log(position);
    })

})