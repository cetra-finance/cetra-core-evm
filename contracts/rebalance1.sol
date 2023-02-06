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
    bool private s_liquidityTokenId;

    // =================================
    // Storage for logic
    // =================================

    //uint256 private immutable i_targetLTV;
    // uint256 private immutable i_minLTV;
    // uint256 private immutable i_maxLTV;

    address private immutable i_usdAddress;
    address private immutable i_wethAddress;
    address private immutable i_wmaticAddress;

    IAaveOracle private immutable i_aaveOracle;
    ICreditDelegationToken private immutable i_aaveWmatic;
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
        address _wmaticAddress,
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
        i_wmaticAddress = _wmaticAddress;
        i_uniswapRouter = IV3SwapRouter(_uniswapRouterAddress);
        i_uniswapPool = IUniswapV3Pool(_uniswapPoolAddress);
        i_aaveWTG3 = IWETHGateway(_aaveWTG3Address);
        i_aaveV3Pool = IPool(_aaveV3poolAddress);
        i_aaveWmatic = ICreditDelegationToken(_aaveVWETHAddress);
        i_aaveOracle = IAaveOracle(_aaveOracleAddress);
        i_uniswapNFTManager = INonfungiblePositionManager(
            _uniswapNFTManagerAddress
        );
        //i_targetLTV = _targetLTV;
    }

    // =================================
    // Mint
    // =================================

    function mintLiquidity(uint256 usdAmount) public {

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

        i_aaveV3Pool.supply(
                i_usdAddress,
                usdAmount,
                address(this),
                0
            );

        if (s_liquidityTokenId) {
            // (
            //     uint256 amount0,
            //     uint256 amount1
            // ) = calculateVirtPositionReserves();

            // uint256 usdToCollateral = (PRECISION * usdAmount) /
            //     (PRECISION +
            //         ((((PRECISION * getUsdOraclePrice()) /
            //             getWethOraclePrice()) * 1e12) *
            //             currentLTV() *
            //             amount1) /
            //         PRECISION /
            //         amount0);
            // console.log("usd goes to collateral", usdToCollateral);

            // i_aaveV3Pool.supply(
            //     i_usdAddress,
            //     usdToCollateral,
            //     address(this),
            //     0
            // );

            // i_aaveWTG3.borrowETH(
            //     address(i_aaveV3Pool),
            //     ((((usdToCollateral * getUsdOraclePrice()) /
            //         getWethOraclePrice()) * 1e12) * currentLTV()) / PRECISION,
            //     2,
            //     0
            // );

            // (uint160 sqrtRatioX96, , , , , , ) = i_uniswapPool.slot0();

            // uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
            //     sqrtRatioX96,
            //     s_lowerTickOfOurToken.getSqrtRatioAtTick(),
            //     s_upperTickOfOurToken.getSqrtRatioAtTick(),
            //     amount0,
            //     amount1
            // );

            // (bool success, ) = i_wethAddress.call{value: address(this).balance}(abi.encodeWithSignature("deposit"));
            // require(success, "FC1");

            // i_uniswapPool.mint(
            //     address(this),
            //     s_lowerTickOfOurToken,
            //     s_upperTickOfOurToken,
            //     liquidityMinted,
            //     ""
            // );

        } else {
            s_lowerTickOfOurToken = ((getTick() - 200) / 10) * 10;
            s_upperTickOfOurToken = ((getTick() + 200) / 10) * 10;

            uint256 maticToBorrow = ((((usdAmount * 30 / 100) * getUsdOraclePrice()) /
                    getMaticOraclePrice()) * 1e12 * 1e18) / PRECISION;

            i_aaveWTG3.borrowETH(
                address(i_aaveV3Pool),
                maticToBorrow,
                2,
                0
            );

            uint256 wethToBorrow = ((((usdAmount * 30 / 100) * getUsdOraclePrice()) /
                    getWethOraclePrice()) * 1e12 * 1e18) / PRECISION;

            i_aaveV3Pool.borrow(
                i_wethAddress,
                wethToBorrow,
                2,
                0,
                address(this)
                );

            // (
            //     uint256 amount0,
            //     uint256 amount1
            // ) = calculateVirtPositionReserves();

            (uint160 sqrtRatioX96, , , , , , ) = i_uniswapPool.slot0();

            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                s_lowerTickOfOurToken.getSqrtRatioAtTick(),
                s_upperTickOfOurToken.getSqrtRatioAtTick(),
                maticToBorrow,
                wethToBorrow
            );

            console.log('wethToBorrow', wethToBorrow);
            console.log('maticToBorrow', maticToBorrow);
            console.log("matic balance", address(this).balance);
            console.log("usd balance", IERC20(i_usdAddress).balanceOf(address(this)));
            console.log("weth balance", IERC20(i_wethAddress).balanceOf(address(this)));
            console.log("wmatic balance", IERC20(i_wmaticAddress).balanceOf(address(this)));

            console.log("----------------");

            (bool success, ) = i_wmaticAddress.call{value: address(this).balance}(abi.encodeWithSignature("deposit"));
            require(success, "FC1");

            console.log('wethToBorrow', wethToBorrow);
            console.log('maticToBorrow', maticToBorrow);
            console.log("matic balance", address(this).balance);
            console.log("usd balance", IERC20(i_usdAddress).balanceOf(address(this)));
            console.log("weth balance", IERC20(i_wethAddress).balanceOf(address(this)));
            console.log("wmatic balance", IERC20(i_wmaticAddress).balanceOf(address(this)));

            console.log("liquidity minted", liquidityMinted);
            console.logInt(s_lowerTickOfOurToken);
            console.logInt(s_upperTickOfOurToken);

            i_uniswapPool.mint(
                address(this),
                s_lowerTickOfOurToken,
                s_upperTickOfOurToken,
                liquidityMinted,
                ""
            );
            
            console.log("----------------");

            console.log("matic balance", address(this).balance);
            console.log("usd balance", IERC20(i_usdAddress).balanceOf(address(this)));
            console.log("weth balance", IERC20(i_wethAddress).balanceOf(address(this)));
            console.log("wmatic balance", IERC20(i_wmaticAddress).balanceOf(address(this)));

            s_liquidityTokenId = true;

        }

        (uint256 liquidAtPosition,,,,) = i_uniswapPool.positions(keccak256(abi.encodePacked(address(this), s_lowerTickOfOurToken, s_upperTickOfOurToken)));
        console.log("liquidAtPosition", liquidAtPosition);
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata /*_data*/
    ) external {
        require(msg.sender == address(i_uniswapPool), "callback caller");

        console.log("amount0Owed", amount0Owed);
        console.log("amount1Owed", amount1Owed);

        if (amount0Owed > 0) TransferHelper.safeTransfer(i_wethAddress, msg.sender, amount0Owed);
        if (amount1Owed > 0) TransferHelper.safeTransfer(i_usdAddress, msg.sender, amount1Owed);
    }

    // =================================
    // Withdraw
    // =================================

    // function withdraw (
    //     uint256 _shares
    // ) public {}

    // =================================
    // FallBack
    // =================================

    receive() external payable {}

    // fallback() external payable {}

    // =================================
    // View funcitons
    // =================================

    function currentLTV() public pure returns (uint256) {
        // return currentETHBorrowed * getWethOraclePrice() / currentUSDInCollateral/getUsdOraclePrice()
        return 100 * 1e16;
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

    function getMaticOraclePrice() public view returns (uint256) {
        return i_aaveOracle.getAssetPrice(i_wmaticAddress);
    }

    function abs(int x) private pure returns (int) {
        return x >= 0 ? x : -x;
    }

    function getLiquidityTokenId() public view returns (bool) {
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
            address(i_aaveWmatic),
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
            address(i_aaveWmatic),
            type(uint256).max
        );  

        TransferHelper.safeApprove(
            i_wmaticAddress,
            address(i_aaveWTG3),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wmaticAddress,
            address(i_uniswapRouter),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wmaticAddress,
            address(i_uniswapNFTManager),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wmaticAddress,
            address(i_uniswapPool),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wmaticAddress,
            address(i_aaveWTG3),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wmaticAddress,
            address(i_aaveWmatic),
            type(uint256).max
        );  

        i_aaveWmatic.approveDelegation(address(i_aaveWTG3), type(uint256).max);
    }
}