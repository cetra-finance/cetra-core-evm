const { ethers } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");
const fs = require("fs");

async function enterChamber() {
    const currNetworkConfig = networkConfig[network.config.chainId];
    let usd = await ethers.getContractAt(
        "IERC20",
        currNetworkConfig.usdcAddress
    );
    snx = await ethers.getContractAt("IERC20", currNetworkConfig.snxAddress);
    let chamber = await ethers.getContractAt(
        "ChamberV1_WETHSNX_Sonne",
        "0x4F46191bC4865813cbd2Ea583046BEa165b7Af8F"
    );
    let tx3 = await chamber.giveApprove(snx.address, currNetworkConfig.soSNX);
    const tx3R = await tx3.wait(1);
    let tx1 = await usd.approve(chamber.address, "10000000000000000");
    const tx1R = await tx1.wait(1);
    let tx2 = await chamber.mint("5000000");
    const tx2R = await tx2.wait(1);

    console.log(tx1R, tx2R, tx3R);
}

enterChamber()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
