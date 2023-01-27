// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Uniswap/libraries/TickMath.sol";
import "./Uniswap/libraries/SqrtPriceMath.sol";

import "./AaveInterfaces/aaveIWETHGateway.sol";
import "./AaveInterfaces/aaveIPool.sol";
import "./Uniswap/IV3SwapRouter.sol";
import "./Uniswap/IUniswapV3Pool.sol";
import "./Uniswap/INonfungiblePositionManager.sol";
import "./AaveInterfaces/ICreditDelegationToken.sol";

import "./TransferHelper.sol";

import "hardhat/console.sol";

contract Rebalance1 is ERC20 {

    // =================================
	// Storage for pool
	// =================================

    uint256 public usdBalance;
    
    // =================================
	// Storage for logic
	// =================================

    address public usd;
    address public weth;
    ICreditDelegationToken public aaveWeth;

    IWETHGateway public aaveWTG3;
    IPool public aaveV3pool;

    IV3SwapRouter public uniswapRouter;
    IUniswapV3Pool public uniswapPool;
    INonfungiblePositionManager public uniswapPositionNFT;

    uint256 public liquididtyTokenId;
    int24 lowerTickOfOurToken;
    int24 upperTickOfOurToken;
    uint128 public ourLiquidity;

    // =================================
	// Temporary solution for testing
	// =================================

    function giveAllApproves() public {
        TransferHelper.safeApprove(usd, address(aaveV3pool), type(uint256).max);
        TransferHelper.safeApprove(usd, address(uniswapRouter), type(uint256).max);
        TransferHelper.safeApprove(usd, address(uniswapPositionNFT), type(uint256).max);
        TransferHelper.safeApprove(usd, address(uniswapPool), type(uint256).max);
        TransferHelper.safeApprove(usd, address(aaveWTG3), type(uint256).max);
        TransferHelper.safeApprove(usd, address(aaveWeth), type(uint256).max);

        TransferHelper.safeApprove(weth, address(aaveWTG3), type(uint256).max);
        TransferHelper.safeApprove(weth, address(uniswapRouter), type(uint256).max);
        TransferHelper.safeApprove(weth, address(uniswapPositionNFT), type(uint256).max);
        TransferHelper.safeApprove(weth, address(uniswapPool), type(uint256).max);
        TransferHelper.safeApprove(weth, address(aaveWTG3), type(uint256).max);
        TransferHelper.safeApprove(weth, address(aaveWeth), type(uint256).max);

        aaveWeth.approveDelegation(address(aaveWTG3), type(uint256).max);
    }

    // =================================
	// View funcitons
	// =================================


    function sharesWorth(uint256 shares) public view returns (uint256) {
        return (usdBalance * shares) / totalSupply();
    }

    function getTick() public view returns(int24) {
        (,int24 tick,,,,,) = uniswapPool.slot0();
        return tick;
    }

    function getPrice() public view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = uniswapPool.slot0();
        return uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18 >> (96*2);
    }

    // function getLiquididtyOfToken() public view returns (uint256) {
    //     (,,,,,uint128 liquididty,,,,) = uniswapPositionNFT.positions(liquididtyTokenId);
    //     return uint256(liquididty);
    // }

    // function getLowerAndUpperTicks() public view returns (int24, int24) {
    //     (,,,,,int24 tickLower,int24 tickUpper,,,,,) = uniswapPositionNFT.positions(liquididtyTokenId);
    //     return (tickLower, tickUpper);
    // }

    function calculateBalanceBetweenTokensForRebalance(
        uint256 _amount
    ) public view returns (uint256, uint256, uint256, uint256, uint256) {
        uint256 amount0USD = 0;
        uint256 amount1USD = 0;
        uint256 amount0Pool = 0;
        uint256 amount1Pool = 0;

        int24 currentTick = getTick();

        if (currentTick < lowerTickOfOurToken) {
            amount0USD = _amount;
        } else if (currentTick > upperTickOfOurToken) {
            amount1USD = _amount;
        } else {
            amount0Pool = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtRatioAtTick(currentTick),
                TickMath.getSqrtRatioAtTick(upperTickOfOurToken),
                1000000000000000000,
                false
            );
            amount1Pool = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(lowerTickOfOurToken),
                TickMath.getSqrtRatioAtTick(currentTick),
                1000000000000000000,
                false
            );
            amount0USD =
                ((_amount * amount0Pool * getPrice()) / 1e18) /
                (amount1Pool + (amount0Pool * getPrice()) / 1e18);
            amount1USD =
                (_amount * amount1Pool) /
                (amount1Pool + (amount0Pool * getPrice()) / 1e18);
        }

        return (
            amount0USD,
            amount1USD,
            (amount0Pool * getPrice()) / 1e18,
            amount1Pool,
            getPrice()
        );
    }

    function calculateBalanceBetweenTokensForMint(
        uint256 _amount
    ) public returns (uint256, uint256, uint256, uint256, uint256) {
        uint256 amount0USD = 0;
        uint256 amount1USD = 0;
        uint256 amount0Pool = 0;
        uint256 amount1Pool = 0;

        int24 currentTick = getTick();
        lowerTickOfOurToken = (currentTick - 200) / 10 * 10;
        upperTickOfOurToken = (currentTick + 200) / 10 * 10;

        if (currentTick < lowerTickOfOurToken) {
            amount0USD = _amount;
        } else if (currentTick > upperTickOfOurToken) {
            amount1USD = _amount;
        } else {
            amount0Pool = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtRatioAtTick(currentTick),
                TickMath.getSqrtRatioAtTick(upperTickOfOurToken),
                1000000000000000000,
                false
            );
            amount1Pool = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(lowerTickOfOurToken),
                TickMath.getSqrtRatioAtTick(currentTick),
                1000000000000000000,
                false
            );
            amount0USD =
                ((_amount * amount0Pool * getPrice()) / 1e18) /
                (amount1Pool + (amount0Pool * getPrice()) / 1e18);
            amount1USD =
                (_amount * amount1Pool) /
                (amount1Pool + (amount0Pool * getPrice()) / 1e18);
        }

        return (
            amount0USD,
            amount1USD,
            (amount0Pool * getPrice()) / 1e18,
            amount1Pool,
            getPrice()
        );
    }

    function abs(int x) private pure returns (int) {
        return x >= 0 ? x : -x;
    }

    // =================================
	// Main funciton
	// =================================

    function addLiqudityToOurPosition(uint256 _amount) public {

        usdBalance += _amount;
        uint256 sharesToGive = (usdBalance != _amount)
            ? ((_amount * totalSupply()) / (usdBalance - _amount))
            : _amount;

        _mint(msg.sender, sharesToGive);

        require(sharesWorth(sharesToGive) <= _amount, "FC0");

        TransferHelper.safeTransferFrom(usd, msg.sender, address(this), _amount);

        if (liquididtyTokenId != 0) {

            (uint256 ethCoef,uint256 usdCoef,,,) = calculateBalanceBetweenTokensForRebalance(_amount);

            aaveV3pool.supply(usd, ethCoef, address(this), 0);
            uint256 ethAmount = (ethCoef * 1e18 / getPrice()) * 60 / 100;
            aaveWTG3.borrowETH(address(aaveV3pool), ethAmount, 2, 0);

            (uint128 tempr,,) = uniswapPositionNFT.increaseLiquidity{value: ethAmount}(
                INonfungiblePositionManager.IncreaseLiquidityParams
                ({
                    tokenId: liquididtyTokenId,
                    amount0Desired: ethAmount,
                    amount1Desired: usdCoef * 60 / 100,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 2 hours
                })
            );
            ourLiquidity += tempr;

            // это остаток от транзакции, который надо будет грамотно распределить между бороуингом и прямым депом в пул
            TransferHelper.safeTransfer(usd, msg.sender, usdCoef * 40 / 100);

        } else {

            (uint256 ethCoef,uint256 usdCoef,,,) = calculateBalanceBetweenTokensForMint(_amount);

            aaveV3pool.supply(usd, ethCoef, address(this), 0);
            uint256 ethAmount = (ethCoef * 1e18 / getPrice()) * 60 / 100;
            aaveWTG3.borrowETH(address(aaveV3pool), ethAmount, 2, 0);

            // int24 currectTick = getTick();
            // lowerTickOfOurToken = (currectTick - 200) / 10 * 10;
            // upperTickOfOurToken = (currectTick + 200) / 10 * 10;

            (liquididtyTokenId,ourLiquidity,,) = uniswapPositionNFT.mint{value: ethAmount}(
                INonfungiblePositionManager.MintParams
                ({
                    token0: weth,
                    token1: usd,
                    fee: 500,
                    tickLower: lowerTickOfOurToken,
                    tickUpper: upperTickOfOurToken,
                    amount0Desired: ethAmount,
                    amount1Desired: usdCoef * 60 / 100,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp + 2 hours
                })
            );

            // это остаток от транзакции, который надо будет грамотно распределить между бороуингом и прямым депом в пул
            TransferHelper.safeTransfer(usd, msg.sender, usdCoef * 40 / 100);
        }
        
    }

    function withdrawLiqudityFromOurPosition(
        uint256 _shares
    ) public {

        // console.log("ourLiquidity", ourLiquidity);
        uint128 liquidity = uint128(ourLiquidity * sharesWorth(_shares) / totalSupply());
        // console.log("liquidity", liquidity);
        ourLiquidity -= liquidity;

        (uint256 amount0, uint256 amount1) = uniswapPositionNFT.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: liquididtyTokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 2 hours
            })
        );

        uniswapPositionNFT.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: liquididtyTokenId,
                recipient: address(0),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        uniswapPositionNFT.unwrapWETH9(0, address(this));
        uniswapPositionNFT.sweepToken(usd, 0, address(this));

        // console.log("amount0", amount0);
        // console.log("amount1", amount1);

        // console.log("eth balance", address(this).balance);
        // console.log("usd balance", IERC20(usd).balanceOf(address(this)));
        // console.log("weth balance", IERC20(weth).balanceOf(address(this)));

        aaveWTG3.repayETH{value: amount0}(address(aaveV3pool), amount0, 2, address(this));
        // console.log("repay done");
        uint256 amountToWithdraw = amount0 * getPrice() *  1666 / 1e18 / 1000;
        // console.log("amountToWithdraw", amountToWithdraw);
        aaveV3pool.withdraw(usd, amountToWithdraw, address(this));

        uint256 usdToReturn = sharesWorth(_shares);
        // console.log("usdToReturn", usdToReturn);
        // console.log("usdToReturn * 80 / 100", usdToReturn * 80 / 100);
        // console.log("eth balance", address(this).balance);
        // console.log("usd balance", IERC20(usd).balanceOf(address(this)));
        // console.log("weth balance", IERC20(weth).balanceOf(address(this)));
        _burn(msg.sender, _shares);
        usdBalance -= usdToReturn;
        console.log(amountToWithdraw + ((usdToReturn - amountToWithdraw) * 60 / 100));
        console.log(usdToReturn * 80 / 100);
        TransferHelper.safeTransfer(usd, msg.sender, (usdToReturn * 80 / 100));
    }

    function rebalancePosition() public {}

    // =================================
	// FallBack
	// =================================

    receive() external payable {}

    // =================================
	// Constructor
	// =================================

    constructor(address _usd, address _weth, address _uniswapRouter, address _uniswapPool, address _aaveWTG3, address _aaveV3pool, address _aaveWeth, address _uniswapPositionNFT)
    ERC20("FirstRebalanceTry", "FRT") 
    {
        usd = _usd;
        weth = _weth;
        uniswapRouter = IV3SwapRouter(_uniswapRouter);
        uniswapPool = IUniswapV3Pool(_uniswapPool);
        aaveWTG3 = IWETHGateway(_aaveWTG3);
        aaveV3pool = IPool(_aaveV3pool);
        aaveWeth = ICreditDelegationToken(_aaveWeth);
        uniswapPositionNFT = INonfungiblePositionManager(_uniswapPositionNFT);
    }

}