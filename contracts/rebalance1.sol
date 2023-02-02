// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./Uniswap/utils/LiquidityAmounts.sol";
import "./Uniswap/libraries/TickMath.sol";
import "./Uniswap/libraries/SqrtPriceMath.sol";
import "./Uniswap/interfaces/IV3SwapRouter.sol";
import "./Uniswap/interfaces/IUniswapV3Pool.sol";
import "./Uniswap/interfaces/INonfungiblePositionManager.sol";

import "./AaveInterfaces/aaveIPool.sol";
import "./AaveInterfaces/aaveIWETHGateway.sol";
import "./AaveInterfaces/ICreditDelegationToken.sol";
import "./AaveInterfaces/IAaveOracle.sol";

import "./TransferHelper.sol";

import "hardhat/console.sol";

contract Rebalance1 is ERC20 {

    using TickMath for int24;

    // =================================
    // Storage for pool
    // =================================

    uint256 private s_usdBalance;
    int24 private s_lowerTickOfOurToken;
    int24 private s_upperTickOfOurToken;
    uint256 private s_liquidityTokenId;

    // =================================
    // Storage for logic
    // =================================

    //uint256 private immutable i_targetLTV;
    // uint256 private immutable i_minLTV;
    // uint256 private immutable i_maxLTV;

    address private immutable i_usdAddress;
    address private immutable i_wethAddress;

    IAaveOracle private immutable i_aaveOracle;
    ICreditDelegationToken private immutable i_aaveWeth;
    IWETHGateway private immutable i_aaveWTG3;
    IPool private immutable i_aaveV3Pool;

    IV3SwapRouter private immutable i_uniswapRouter;
    IUniswapV3Pool private immutable i_uniswapPool;
    INonfungiblePositionManager private immutable i_uniswapNFTManager;

    uint256 private constant PRECISION = 1e18;

    // =================================
    // Constructor
    // =================================

    constructor(
        address _usdAddress,
        address _wethAddress,
        address _uniswapRouterAddress,
        address _uniswapPoolAddress,
        address _aaveWTG3Address,
        address _aaveV3poolAddress,
        address _aaveVWETHAddress,
        address _aaveOracleAddress,
        address _uniswapNFTManagerAddress
    )
        //uint256 _targetLTV
        ERC20("FirstRebalanceTry", "FRT")
    {
        i_usdAddress = _usdAddress;
        i_wethAddress = _wethAddress;
        i_uniswapRouter = IV3SwapRouter(_uniswapRouterAddress);
        i_uniswapPool = IUniswapV3Pool(_uniswapPoolAddress);
        i_aaveWTG3 = IWETHGateway(_aaveWTG3Address);
        i_aaveV3Pool = IPool(_aaveV3poolAddress);
        i_aaveWeth = ICreditDelegationToken(_aaveVWETHAddress);
        i_aaveOracle = IAaveOracle(_aaveOracleAddress);
        i_uniswapNFTManager = INonfungiblePositionManager(
            _uniswapNFTManagerAddress
        );
        //i_targetLTV = _targetLTV;
    }

    // =================================
    // Main funciton
    // =================================

    function mint(uint256 usdAmount) public {
        s_usdBalance += usdAmount;
        uint256 sharesToMint = (s_usdBalance != usdAmount)
            ? ((usdAmount * totalSupply()) / (s_usdBalance - usdAmount))
            : usdAmount;
        _mint(msg.sender, sharesToMint);
        require(sharesWorth(sharesToMint) <= usdAmount, "FC0");
        TransferHelper.safeTransferFrom(
            i_usdAddress,
            msg.sender,
            address(this),
            usdAmount
        );

        if (s_liquidityTokenId != 0) {
            (
                uint256 amount0,
                uint256 amount1
            ) = calculateVirtPositionReserves();

            uint256 usdToCollateral = (PRECISION * usdAmount) /
                (PRECISION +
                    ((((PRECISION * getUsdOraclePrice()) /
                        getWethOraclePrice()) * 1e12) *
                        currentLTV() *
                        amount1) /
                    PRECISION /
                    amount0);
            console.log("usd goes to collateral", usdToCollateral);

            i_aaveV3Pool.supply(
                i_usdAddress,
                usdToCollateral,
                address(this),
                0
            );

            i_aaveWTG3.borrowETH(
                address(i_aaveV3Pool),
                ((((usdToCollateral * getUsdOraclePrice()) /
                    getWethOraclePrice()) * 1e12) * currentLTV()) / PRECISION,
                2,
                0
            );

            i_uniswapNFTManager.increaseLiquidity{
                value: ((((usdToCollateral * getUsdOraclePrice()) /
                    getWethOraclePrice()) * 1e12) * currentLTV()) / PRECISION
            }(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: s_liquidityTokenId,
                    amount0Desired: ((((usdToCollateral * getUsdOraclePrice()) /
                        getWethOraclePrice()) * 1e12) * currentLTV()) /
                        PRECISION,
                    amount1Desired: usdAmount - usdToCollateral,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 2 hours
                })
            );
        } else {
            s_lowerTickOfOurToken = ((getTick() - 200) / 10) * 10;
            s_upperTickOfOurToken = ((getTick() + 200) / 10) * 10;

            (
                uint256 amount0,
                uint256 amount1
            ) = calculateVirtPositionReserves();

            uint256 usdToCollateral = (PRECISION * usdAmount) /
                (PRECISION +
                    (((((PRECISION * getUsdOraclePrice()) /
                        getWethOraclePrice()) * 1e12) *
                        670000000000000000 *
                        amount1) / PRECISION) /
                    amount0);
            console.log("usd goes to collateral", usdToCollateral);

            i_aaveV3Pool.supply(
                i_usdAddress,
                usdToCollateral,
                address(this),
                0
            );

            i_aaveWTG3.borrowETH(
                address(i_aaveV3Pool),
                ((((usdToCollateral * getUsdOraclePrice()) /
                    getWethOraclePrice()) * 1e12) * 670000000000000000) /
                    PRECISION,
                2,
                0
            );

            (uint160 sqrtRatioX96, , , , , , ) = i_uniswapPool.slot0();

            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                s_lowerTickOfOurToken.getSqrtRatioAtTick(),
                s_upperTickOfOurToken.getSqrtRatioAtTick(),
                amount0,
                amount1
            );

            i_uniswapPool.mint(
                address(this),
                s_lowerTickOfOurToken,
                s_upperTickOfOurToken,
                liquidityMinted,
                ""
            );

            // (s_liquidityTokenId, , , ) = i_uniswapNFTManager.mint{
            //     value: ((((usdToCollateral * getUsdOraclePrice()) /
            //         getWethOraclePrice()) * 1e12) * 670000000000000000) /
            //         PRECISION
            // }(
            //     INonfungiblePositionManager.MintParams({
            //         token0: i_wethAddress,
            //         token1: i_usdAddress,
            //         fee: 500,
            //         tickLower: s_lowerTickOfOurToken,
            //         tickUpper: s_upperTickOfOurToken,
            //         amount0Desired: ((((usdToCollateral * getUsdOraclePrice()) /
            //             getWethOraclePrice()) * 1e12) * 670000000000000000) /
            //             PRECISION,
            //         amount1Desired: usdAmount - usdToCollateral,
            //         amount0Min: 0,
            //         amount1Min: 0,
            //         recipient: address(this),
            //         deadline: block.timestamp + 2 hours
            //     })
            // );
        }
    }

    // =================================
    // FallBack
    // =================================

    receive() external payable {}

    // =================================
    // View funcitons
    // =================================

    function currentLTV() public pure returns (uint256) {
        // return currentETHBorrowed * getWethOraclePrice() / currentUSDInCollateral/getUsdOraclePrice()
        return 67 * 1e16;
    }

    function sharesWorth(uint256 shares) public view returns (uint256) {
        return (s_usdBalance * shares) / totalSupply();
    }

    function getTick() public view returns (int24) {
        (, int24 tick, , , , , ) = i_uniswapPool.slot0();
        return tick;
    }

    function getUsdOraclePrice() public view returns (uint256) {
        return i_aaveOracle.getAssetPrice(i_usdAddress);
    }

    function getWethOraclePrice() public view returns (uint256) {
        return i_aaveOracle.getAssetPrice(i_wethAddress);
    }

    function abs(int x) private pure returns (int) {
        return x >= 0 ? x : -x;
    }

    function getLiquidityTokenId() public view returns (uint256) {
        return s_liquidityTokenId;
    }

    function getPositionLiquidity() public view returns (uint128) {
        // (, , , , , , , uint128 liquidity, , , , ) = i_uniswapNFTManager
        //     .positions(s_liquidityTokenId);
        // (uint128 liq,,,,)= i_uniswapPool.positions(keccak256(abi.encodePacked(address(this), s_lowerTickOfOurToken, s_upperTickOfOurToken)));
        // console.log("liquidity", liq);
        return 9194295139235952;
    }

    function calculateVirtPositionReserves()
        public
        view
        returns (uint256, uint256)
    {
        uint256 amount0 = 0;
        uint256 amount1 = 0;

        if (getTick() < s_lowerTickOfOurToken) {
            amount0 = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtRatioAtTick(s_lowerTickOfOurToken),
                TickMath.getSqrtRatioAtTick(s_upperTickOfOurToken),
                1000000000000000,
                false
            );
        } else if (getTick() > s_upperTickOfOurToken) {
            amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(s_lowerTickOfOurToken),
                TickMath.getSqrtRatioAtTick(s_upperTickOfOurToken),
                1000000000000000,
                false
            );
        } else {
            amount0 = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtRatioAtTick(getTick()),
                TickMath.getSqrtRatioAtTick(s_upperTickOfOurToken),
                1000000000000000,
                false
            );
            amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(s_lowerTickOfOurToken),
                TickMath.getSqrtRatioAtTick(getTick()),
                1000000000000000,
                false
            );
        }
        return (amount0, amount1);
    }

    function calculateCurrentPositionReserves()
        public
        view
        returns (uint256, uint256)
    {
        uint256 amount0 = 0;
        uint256 amount1 = 0;

        if (getTick() < s_lowerTickOfOurToken) {
            amount0 = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtRatioAtTick(s_lowerTickOfOurToken),
                TickMath.getSqrtRatioAtTick(s_upperTickOfOurToken),
                getPositionLiquidity(),
                false
            );
        } else if (getTick() > s_upperTickOfOurToken) {
            amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(s_lowerTickOfOurToken),
                TickMath.getSqrtRatioAtTick(s_upperTickOfOurToken),
                getPositionLiquidity(),
                false
            );
        } else {
            amount0 = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtRatioAtTick(getTick()),
                TickMath.getSqrtRatioAtTick(s_upperTickOfOurToken),
                getPositionLiquidity(),
                false
            );
            amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(s_lowerTickOfOurToken),
                TickMath.getSqrtRatioAtTick(getTick()),
                getPositionLiquidity(),
                false
            );
        }
        return (amount0, amount1);
    }

    // =================================
    // Temporary solution for testing
    // =================================

    function giveAllApproves() public {
        TransferHelper.safeApprove(
            i_usdAddress,
            address(i_aaveV3Pool),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_usdAddress,
            address(i_uniswapRouter),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_usdAddress,
            address(i_uniswapNFTManager),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_usdAddress,
            address(i_uniswapPool),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_usdAddress,
            address(i_aaveWTG3),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_usdAddress,
            address(i_aaveWeth),
            type(uint256).max
        );

        TransferHelper.safeApprove(
            i_wethAddress,
            address(i_aaveWTG3),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wethAddress,
            address(i_uniswapRouter),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wethAddress,
            address(i_uniswapNFTManager),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wethAddress,
            address(i_uniswapPool),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wethAddress,
            address(i_aaveWTG3),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wethAddress,
            address(i_aaveWeth),
            type(uint256).max
        );

        i_aaveWeth.approveDelegation(address(i_aaveWTG3), type(uint256).max);
    }
}