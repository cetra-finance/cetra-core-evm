// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./AaveInterfaces/aaveIWETHGateway.sol";
import "./AaveInterfaces/aaveIPool.sol";
import "./Uniswap/IV3SwapRouter.sol";
import "./Uniswap/IUniswapV3Pool.sol";
import "./Uniswap/INonfungiblePositionManager.sol";
import "./AaveInterfaces/ICreditDelegationToken.sol";

import "./TransferHelper.sol";

import "hardhat/console.sol";

contract FirstRebalanceTry is ERC20 {

    using SafeMath for uint256;

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

    // =================================
	// Our pool
	// =================================

    function sharesWorth(uint256 shares) public view returns (uint256) {
        return (usdBalance * shares) / totalSupply();
    }

    function depositToPool(uint256 _amount) public {
        uint256 sharesToGive = (usdBalance != _amount)
            ? ((_amount * totalSupply()) / (usdBalance - _amount))
            : _amount;

        usdBalance += _amount;
        _mint(msg.sender, sharesToGive);

        require(sharesWorth(sharesToGive) <= _amount);

        TransferHelper.safeTransferFrom(usd, msg.sender, address(this), _amount);
    }

    function withdrawFromPool(uint256 _amount) public {
        uint256 etherToReturn = sharesWorth(_amount);
        _burn(msg.sender, _amount);
        TransferHelper.safeTransfer(usd, msg.sender, etherToReturn);
    }

    // =================================
	// Approve
	// =================================

    function giveApprove(address _token, address _spender, uint256 _amount) public {
        TransferHelper.safeApprove(_token, _spender, _amount);
    }

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
	// Aave deposit and withdraw
	// =================================

    function depositToAvee() public payable {
        TransferHelper.safeTransferFrom(usd, msg.sender, address(this), 2500000000);
        TransferHelper.safeApprove(usd, address(aaveV3pool), 2500000000);

        aaveV3pool.supply(usd, 2000000000, address(this), 0);
    }

    function withdrawFromAave(uint256 _amount) public {
        aaveV3pool.withdraw(usd, 2000000000, address(this));
    }

    // =================================
	// Aave borrow and repay
	// =================================

    function borrowFromAave() public {
        aaveWeth.approveDelegation(address(aaveWTG3), 1157920892373161954235709850090785326998466564056403945758400791312963);
        console.log("ggggg");
        aaveWTG3.borrowETH(address(aaveV3pool), 100000000000000000, 2, 0);
    }

    function repayToAave() public {
        aaveWTG3.repayETH(address(aaveV3pool), 100000000000000000, 2, address(this));
    }

    function getUserAccountData() public view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        return IPool(aaveV3pool).getUserAccountData(address(this));
    }

    // =================================
	// Uniswap swap
	// =================================

    function makeSwap() public {
        uint160 _sqrtPriceX96 = getSqrt();

        TransferHelper.safeTransferFrom(usd, msg.sender, address(this), 1500000000);
        TransferHelper.safeApprove(usd, address(uniswapRouter), 2000000000000000000);

            uniswapRouter.exactOutputSingle(IV3SwapRouter.ExactOutputSingleParams({
                tokenIn: usd,
                tokenOut: weth,
                fee: 500,
                recipient: address(this),
                amountOut: 500000000000000000,
                amountInMaximum: 1500000000,
                sqrtPriceLimitX96: 0 // _sqrtPriceX96
            }));
    }

    // =================================
	// Uniswap liquidity
	// =================================

    function getTick() public view returns(int24) {
        (,int24 tick,,,,,) = uniswapPool.slot0();
        return tick;
    }

    function getPrice() public view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = uniswapPool.slot0();
        return uint256(sqrtPriceX96).mul(uint256(sqrtPriceX96)).mul(1e18) >> (96*2);
    }

    function getPriceUSD(uint256 amount) public view returns (uint256) {
        return (amount * 1e18 / getPrice() / 2) * 60 / 100;
    }

    function getSqrt() public view returns (uint160) {
        (uint160 sqrtPriceX96,,,,,,) = uniswapPool.slot0();
        return sqrtPriceX96;
    }

    function addLuquidityToUniswap() external payable {
        TransferHelper.safeApprove(usd, address(uniswapPositionNFT), 10000000000000000000000);
        TransferHelper.safeApprove(weth, address(uniswapPositionNFT), 10000000000000000000000);
        TransferHelper.safeTransferFrom(usd, msg.sender, address(this), 1500000000);
        TransferHelper.safeTransferFrom(weth, msg.sender, address(this), 1000000000000000000);

        int24 currectTick = getTick();

        console.log("sdoneeee");

        (liquididtyTokenId,,,) = uniswapPositionNFT.mint(INonfungiblePositionManager.MintParams({
            token0: weth,
            token1: usd,
            fee: 500,
            tickLower: (currectTick - 200) / 10 * 10,
            tickUpper: (currectTick + 200) / 10 * 10,
            amount0Desired: 1000000000000000000,
            amount1Desired: 1000000000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        }));
    }

    // =================================
	// Funciton of full circuit
	// =================================

    function fullCircle(uint256 amount) public {

        TransferHelper.safeTransferFrom(usd, msg.sender, address(this), amount);

        console.log("gggg");

        aaveV3pool.supply(usd, amount/2, address(this), 0);
        uint256 ethAmount = (amount * 1e18 / getPrice() / 2) * 60 / 100;

        console.log("jjjj");

        aaveWTG3.borrowETH(address(aaveV3pool), ethAmount, 2, 0);

        console.log("tttt");

        int24 currectTick = getTick();
        (liquididtyTokenId,,,) = uniswapPositionNFT.mint(INonfungiblePositionManager.MintParams({
            token0: weth,
            token1: usd,
            fee: 500,
            tickLower: (currectTick - 200) / 10 * 10,
            tickUpper: (currectTick + 200) / 10 * 10,
            amount0Desired: ethAmount,
            amount1Desired: amount/2,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        }));
        
    }

    // =================================
	// fallBack
	// =================================

    receive() external payable {
        console.log("receive");
    }

    fallback() external payable {
        // can be empty
    }

    // function fallback() public payable {
    //     console.log("fallback");
    // }

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