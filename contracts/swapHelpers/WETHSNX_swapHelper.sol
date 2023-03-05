// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;

import "../Uniswap/interfaces/ISwapRouter.sol";

import "./ISwapHelper.sol";

contract WETHSNX_swapHelper is ISwapHelper {
    address private constant i_usdcAddress =
        0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address private constant i_token0Address =
        0x4200000000000000000000000000000000000006;
    address private constant i_token1Address =
        0x8700dAec35aF8Ff88c16BdF0418774CB3D7599B4;

    ISwapRouter private constant i_uniswapSwapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    function swapExactAssetToStable(
        address assetIn,
        uint256 amountIn
    ) external override returns (uint256) {
        uint256 amounOut;

        if (assetIn == i_token0Address) {
            amounOut = i_uniswapSwapRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(assetIn, uint24(500), i_usdcAddress),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0
                })
            );
        } else {
            amounOut = i_uniswapSwapRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(
                        assetIn,
                        uint24(3000),
                        i_token0Address,
                        uint24(500),
                        i_usdcAddress
                    ),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0
                })
            );
        }

        return amounOut;
    }

    function swapStableToExactAsset(
        address assetOut,
        uint256 amountOut
    ) external override returns (uint256) {
        uint256 amountIn;
        if (assetOut == i_token0Address) {
            amountIn = i_uniswapSwapRouter.exactOutput(
                ISwapRouter.ExactOutputParams({
                    path: abi.encodePacked(
                        i_token0Address,
                        uint24(500),
                        i_usdcAddress
                    ),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: amountOut,
                    amountInMaximum: 1e50
                })
            );
        } else {
            amountIn = i_uniswapSwapRouter.exactOutput(
                ISwapRouter.ExactOutputParams({
                    path: abi.encodePacked(
                        i_token1Address,
                        uint24(3000),
                        i_token0Address,
                        uint24(500),
                        i_usdcAddress
                    ),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: amountOut,
                    amountInMaximum: 1e50
                })
            );
        }
        return amountIn;
    }

    function swapAssetToExactAsset(
        address assetIn,
        address assetOut,
        uint256 amountOut
    ) external override returns (uint256) {
        uint256 amountIn = i_uniswapSwapRouter.exactOutput(
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(assetOut, uint24(3000), assetIn),
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: type(uint256).max
            })
        );

        return amountIn;
    }
}
