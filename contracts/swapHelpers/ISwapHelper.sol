// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;

interface ISwapHelper {
    function swapExactAssetToStable(address assetIn, uint256 amountIn) external returns (uint256);
    function swapStableToExactAsset(address assetOut, uint256 amountOut) external returns (uint256);
    function swapAssetToExactAsset(address assetIn, address assetOut, uint256 amountOut) external returns (uint256);
}