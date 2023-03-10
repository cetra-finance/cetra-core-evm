// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "./ICErc20.sol";

interface IChainlinkPriceOracle {
    function priceFeeds(string memory _symbol) external view returns (address);
    function getUnderlyingPrice(
        ICErc20 cToken
    ) external view returns (uint256);
}