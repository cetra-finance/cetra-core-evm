// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

    // function getLowerAndUpperTicks() public view returns (int24, int24) {
    //     (,,,,,int24 tickLower,int24 tickUpper,,,,,) = uniswapPositionNFT.positions(liquididtyTokenId);
    //     return (tickLower, tickUpper);
    // }

    function calculateBalanceBetweenTokensForRebalance(uint256 _amount) public view returns (uint256, uint256) {
        int24 currentTick = getTick();

        uint256 amount0 = 0;
        uint256 amount1 = 0;

        if (currentTick < lowerTickOfOurToken) {
            amount0 = _amount;
        } else if (currentTick > upperTickOfOurToken) {
            amount1 = _amount;
        } else {
            amount0 = _amount * uint256(abs(currentTick - lowerTickOfOurToken)) / uint256(abs(upperTickOfOurToken - lowerTickOfOurToken));
            amount1 = _amount * uint256(abs(upperTickOfOurToken - currentTick)) / uint256(abs(upperTickOfOurToken - lowerTickOfOurToken));
        }

        return (amount0, amount1);
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

            (uint256 ethCoef, uint256 usdCoef) = calculateBalanceBetweenTokensForRebalance(_amount);

            aaveV3pool.supply(usd, ethCoef, address(this), 0);
            uint256 ethAmount = (ethCoef * 1e18 / getPrice()) * 60 / 100;
            aaveWTG3.borrowETH(address(aaveV3pool), ethAmount, 2, 0);

            uniswapPositionNFT.increaseLiquidity{value: ethAmount}(
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

            // это остаток от транзакции, который надо будет грамотно распределить между бороуингом и прямым депом в пул
            TransferHelper.safeTransfer(usd, msg.sender, usdCoef * 40 / 100);

        } else {

            aaveV3pool.supply(usd, _amount/2, address(this), 0);
            uint256 ethAmount = (_amount * 1e18 / getPrice() / 2) * 60 / 100;
            aaveWTG3.borrowETH(address(aaveV3pool), ethAmount, 2, 0);

            int24 currectTick = getTick();
            lowerTickOfOurToken = (currectTick - 200) / 10 * 10;
            upperTickOfOurToken = (currectTick + 200) / 10 * 10;

            (liquididtyTokenId,,,) = uniswapPositionNFT.mint{value: ethAmount}(
                INonfungiblePositionManager.MintParams
                ({
                    token0: weth,
                    token1: usd,
                    fee: 500,
                    tickLower: lowerTickOfOurToken,
                    tickUpper: upperTickOfOurToken,
                    amount0Desired: ethAmount,
                    amount1Desired: _amount * 30 / 100,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp + 2 hours
                })
            );

            // это остаток от транзакции, который надо будет грамотно распределить между бороуингом и прямым депом в пул
            TransferHelper.safeTransfer(usd, msg.sender, _amount * 20 / 100);
        }
        
    }

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