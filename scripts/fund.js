const { ethers } = require("hardhat");
const { networkConfig } = require("../../helper-hardhat-config");
const fs = require("fs");

async function enterChamber() {
    const currNetworkConfig = networkConfig[network.config.chainId];
    let usd = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.usdcAddress
    );
    let chamber = await ethers.getContractAt(
        "ChamberV1",
        "0x0AF6aDEa1a5ADA8D1AB05fE06B76aD71f7407a56"
    );
    let tx1 = await usd.approve(chamber.address, "10000000000000000");
    const tx1R = await tx1.wait(1);
    let tx2 = await chamber.mint("10000000");
    const tx2R = await tx2.wait(1);
    console.log(tx1R, tx2R);
}

enterChamber()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
