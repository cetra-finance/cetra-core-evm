// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

interface AccessControlledOffchainAggregator {
    function latestRoundData() external view returns (uint80, int256, int256, int256, int80);
    function trasmit(bytes calldata _report, bytes32[] calldata _rs, bytes32[] calldata _ss, bytes32 _rawVs) external;
}