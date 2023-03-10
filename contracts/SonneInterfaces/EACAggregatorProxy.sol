// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

interface EACAggregatorProxy {
    function aggregator() external view returns (address);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}