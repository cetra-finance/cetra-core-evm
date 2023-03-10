// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

contract sonneOracleReplace {

    int256 public price;

    constructor(int256 _price) {
        price = _price;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (uint80(0), price, uint256(0), uint256(0), uint80(0));
    }

}