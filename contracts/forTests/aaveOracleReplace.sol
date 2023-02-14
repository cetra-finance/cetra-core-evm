// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

contract AaveOracleReplace {

    uint256 public price;

    constructor(uint256 _price) {
        price = _price;
    }

    function latestAnswer() external view returns (uint256) {
        return price;
    }

}