const { ethers } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const fs = require("fs");

async function enterChamber() {
    const currNetworkConfig = networkConfig[network.config.chainId];
    let usd = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.usdcAddress
    );
    let chamber = await ethers.getContractAt(
        "ChamberV1VolStable",
        "0x93e3b2e1e3837622156fecdc6e5472af31fe10bb"
    );
    // let tx1 = await usd.approve(chamber.address, "5000000000000000");
    // const tx1R = await tx1.wait(1);
    // let tx2 = await chamber.mint("1000000");
    // const tx2R = await tx2.wait(1);
    let tx3 = await chamber.burn("1000000");
    const tx3R = await tx2.wait(1);
    // console.log(tx1R, tx2R);
}

enterChamber()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
