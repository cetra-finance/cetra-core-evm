// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "./Uniswap/utils/LiquidityAmounts.sol";
import "./Uniswap/libraries/TickMath.sol";
import "./Uniswap/interfaces/IV3SwapRouter.sol";
import "./Uniswap/interfaces/IUniswapV3Pool.sol";
import "./Uniswap/interfaces/callback/IUniswapV3MintCallback.sol";

import "./AaveInterfaces/IPool.sol";
import "./AaveInterfaces/aaveIWETHGateway.sol";
import "./AaveInterfaces/IAaveOracle.sol";
import "./AaveInterfaces/IAToken.sol";
import "./AaveInterfaces/IVariableDebtToken.sol";

import "./TransferHelper.sol";

import "hardhat/console.sol";

/*Errors */
error ChamberV1__AaveDepositError();

contract ChamberV1 is IUniswapV3MintCallback {

    using TickMath for int24;

    // =================================
    // Storage for users and their deposits
    // =================================

    uint256 public s_totalDeposits;
    mapping(address => uint256) public s_userDeposits;

    // =================================
    // Storage for pool
    // =================================

    uint256 private s_usdBalance;
    int24 private s_lowerTick;
    int24 private s_upperTick;
    bool private s_liquidityTokenId;

    // =================================
    // Storage for logic
    // =================================

    uint256 private s_targetLTV;
    uint256 private s_minLTV;
    uint256 private s_maxLTV;

    address private immutable i_usdcAddress;
    address private immutable i_wethAddress;
    address private immutable i_wmaticAddress;

    IAToken private immutable i_aaveAUSDCToken;
    IVariableDebtToken private immutable i_aaveVWETHToken;
    IVariableDebtToken private immutable i_aaveVWMATICToken;

    IAaveOracle private immutable i_aaveOracle;
    IWETHGateway private immutable i_aaveWTG3;
    IPool private immutable i_aaveV3Pool;

    IV3SwapRouter private immutable i_uniswapSwapRouter;
    IUniswapV3Pool private immutable i_uniswapPool;

    uint256 private constant PRECISION = 1e18;

    // =================================
    // Constructor
    // =================================

    constructor(
        address _uniswapSwapRouterAddress,
        address _uniswapPoolAddress,
        address _aaveWTG3Address,
        address _aaveV3poolAddress,
        address _aaveVWETHAddress,
        address _aaveVWMATICAddress,
        address _aaveOracleAddress,
        address _aaveAUSDCAddress
    )
        //uint256 _targetLTV
    {
        i_uniswapSwapRouter = IV3SwapRouter(_uniswapSwapRouterAddress);
        i_uniswapPool = IUniswapV3Pool(_uniswapPoolAddress);
        i_aaveWTG3 = IWETHGateway(_aaveWTG3Address);
        i_aaveV3Pool = IPool(_aaveV3poolAddress);
        i_aaveOracle = IAaveOracle(_aaveOracleAddress);
        i_aaveAUSDCToken = IAToken(_aaveAUSDCAddress);
        i_aaveVWETHToken = IVariableDebtToken(_aaveVWETHAddress);
        i_aaveVWMATICToken = IVariableDebtToken(_aaveVWMATICAddress);
        i_usdcAddress = i_aaveAUSDCToken.UNDERLYING_ASSET_ADDRESS();
        i_wethAddress = i_aaveVWETHToken.UNDERLYING_ASSET_ADDRESS();
        i_wmaticAddress = i_aaveVWMATICToken.UNDERLYING_ASSET_ADDRESS();
    }

    function setLTV(
        uint256 _targetLTV,
        uint256 _minLTV,
        uint256 _maxLTV
    ) public {
        s_targetLTV = _targetLTV;
        s_minLTV = _minLTV;
        s_maxLTV = _maxLTV;
    }

    /// @notice Uniswap V3 callback fn, called back on pool.mint
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata /*_data*/
    ) external override {
        require(msg.sender == address(i_uniswapPool), "callback caller");

        if (amount0Owed > 0)
            TransferHelper.safeTransfer(i_wmaticAddress, msg.sender, amount0Owed);
        if (amount1Owed > 0)
            TransferHelper.safeTransfer(i_wethAddress, msg.sender, amount1Owed);
    }

    // =================================
    // Main funciton
    // =================================

    function mint(uint256 usdAmount) public {
        {
            uint256 currUsdBalance = currentUSDBalance();
            uint256 sharesToMint = (currUsdBalance != 0)
                ? ((usdAmount * s_totalDeposits) / (currUsdBalance))
                : usdAmount;
            s_totalDeposits += sharesToMint;
            s_userDeposits[msg.sender] += sharesToMint;
            // _mint(msg.sender, sharesToMint);
            require(sharesWorth(sharesToMint) <= usdAmount, "FC0");
            TransferHelper.safeTransferFrom(
                i_usdcAddress,
                msg.sender,
                address(this),
                usdAmount
            );
            // console.log("CURRENT USD BALANCE is", currentUSDBalance());
            // console.log("DEPOSIT's sharesWorth is", sharesWorth(sharesToMint));
        }

        uint256 amount0;
        uint256 amount1;
        uint256 usedLTV;
        if (!s_liquidityTokenId) {
            s_lowerTick = ((getTick() - 400) / 10) * 10;
            s_upperTick = ((getTick() + 800) / 10) * 10;
            (amount0, amount1) = calculateVirtPoolReserves();
            usedLTV = s_targetLTV;
            s_liquidityTokenId = true;
        } else {
            usedLTV = currentLTV();
            (amount0, amount1) = calculateRealPoolReserves();
        }
        // console.log("USING AMOUNTS", amount0, amount1);
        // console.log("USING LTV", usedLTV);

        i_aaveV3Pool.supply(
            i_usdcAddress,
            TransferHelper.safeGetBalance(i_usdcAddress, address(this)),
            address(this),
            0
        );

        uint256 wethToBorrow = (usdAmount * getUsdcOraclePrice() * usedLTV) /
            ((getWmaticOraclePrice() * amount0) /
                amount1 /
                1e12 +
                getWethOraclePrice() /
                1e12) /
            PRECISION;

        uint256 wmaticToBorrow = (usdAmount * getUsdcOraclePrice() * usedLTV) /
            (getWmaticOraclePrice() /
                1e12 +
                (getWethOraclePrice() * amount1) /
                amount0 /
                1e12) /
            PRECISION;

        // console.log("WMATIC wanted to BORROW", wmaticToBorrow);
        i_aaveV3Pool.borrow(
            i_wmaticAddress,
            wmaticToBorrow,
            2,
            0,
            address(this)
        );
        // console.log("MATIC BORROWED", getVWMATICTokenBalance());

        // console.log("WETH wanted to BORROW", wethToBorrow);
        i_aaveV3Pool.borrow(i_wethAddress, wethToBorrow, 2, 0, address(this));
        // console.log("WETH BORROWED", getVWETHTokenBalance());
        {
            uint256 wmaticRecieved = TransferHelper.safeGetBalance(i_wmaticAddress, address(this));
            uint256 wethRecieved = TransferHelper.safeGetBalance(i_wethAddress, address(this));
            (uint160 sqrtRatioX96, , , , , , ) = i_uniswapPool.slot0();
            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                s_lowerTick.getSqrtRatioAtTick(),
                s_upperTick.getSqrtRatioAtTick(),
                wmaticRecieved,
                wethRecieved
            );

            i_uniswapPool.mint(
                address(this),
                s_lowerTick,
                s_upperTick,
                liquidityMinted,
                ""
            );
        }
    }

    function withdraw(
        uint256 _shares
    ) public {
        uint256 usdToReturn = sharesWorth(_shares);
        s_totalDeposits -= _shares;
        s_userDeposits[msg.sender] -= _shares;
        // _burn(msg.sender, _shares);

        console.log("usdToReturn", usdToReturn);

        // console.log("i_wethAddress balance", TransferHelper.safeGetBalance(i_wethAddress, address(this)));
        // console.log("i_wmaticAddress balance", TransferHelper.safeGetBalance(i_wmaticAddress, address(this)));
        // console.log("i_usdcAddress balance", TransferHelper.safeGetBalance(i_usdcAddress, address(this)));
        // console.log("getVWETHTokenBalance", getVWETHTokenBalance());
        // console.log("getVWMATICTokenBalance", getVWMATICTokenBalance());
        // console.log("getAUSDCTokenBalance", getAUSDCTokenBalance());

        {
            (uint128 liquidity, , , , ) = i_uniswapPool.positions(keccak256(abi.encodePacked(address(this), s_lowerTick, s_upperTick)));
            i_uniswapPool.burn(s_lowerTick, s_upperTick, liquidity);

            i_uniswapPool.collect(
                address(this),
                s_lowerTick,
                s_upperTick,
                type(uint128).max,
                type(uint128).max
            );
        }

        console.log("i_wethAddress balance", TransferHelper.safeGetBalance(i_wethAddress, address(this)));
        console.log("i_wmaticAddress balance", TransferHelper.safeGetBalance(i_wmaticAddress, address(this)));
        console.log("i_usdcAddress balance", TransferHelper.safeGetBalance(i_usdcAddress, address(this)));
        console.log("getVWETHTokenBalance", getVWETHTokenBalance());
        console.log("getVWMATICTokenBalance", getVWMATICTokenBalance());
        console.log("getAUSDCTokenBalance", getAUSDCTokenBalance());

        i_aaveV3Pool.repay(
            i_wethAddress,
            TransferHelper.safeGetBalance(i_wethAddress, address(this)),
            2,
            address(this)
        );

        i_aaveV3Pool.repay(
            i_wmaticAddress,
            TransferHelper.safeGetBalance(i_wmaticAddress, address(this)),
            2,
            address(this)
        );

        console.log("---------------------");

        console.log("i_wethAddress balance", TransferHelper.safeGetBalance(i_wethAddress, address(this)));
        console.log("i_wmaticAddress balance", TransferHelper.safeGetBalance(i_wmaticAddress, address(this)));
        console.log("i_usdcAddress balance", TransferHelper.safeGetBalance(i_usdcAddress, address(this)));
        console.log("getVWETHTokenBalance", getVWETHTokenBalance());
        console.log("getVWMATICTokenBalance", getVWMATICTokenBalance());
        console.log("getAUSDCTokenBalance", getAUSDCTokenBalance());

        i_aaveV3Pool.withdraw(
            i_usdcAddress,
            8000000006,
            address(this)
        );

        TransferHelper.safeTransfer(i_usdcAddress, msg.sender, usdToReturn);
    }

    function rebalance() public {}

    // =================================
    // FallBack
    // =================================

    receive() external payable {}

    // =================================
    // View funcitons
    // =================================

    function currentUSDBalance() public view returns (uint256) {
        uint256 usdBalance = _currentUSDBalance();
        return usdBalance;
    }

    function _currentUSDBalance() internal view returns (uint256) {
        (
            uint256 wmaticPoolBalance,
            uint256 wethPoolBalance
        ) = calculateCurrentPositionReserves();
        return (getAUSDCTokenBalance() +
            TransferHelper.safeGetBalance(i_usdcAddress, address(this)) +
            ((wethPoolBalance - getVWETHTokenBalance()) *
                getWethOraclePrice()) /
            PRECISION /
            1e12 +
            ((wmaticPoolBalance - getVWMATICTokenBalance()) *
                getWmaticOraclePrice()) /
            PRECISION /
            1e12);
    }

    function currentLTV() public view returns (uint256) {
        // return currentETHBorrowed * getWethOraclePrice() / currentUSDInCollateral/getUsdOraclePrice()
        (
            uint256 totalCollateralETH,
            uint256 totalBorrowedETH,
            ,
            ,
            ,

        ) = i_aaveV3Pool.getUserAccountData(address(this));
        return (PRECISION * totalBorrowedETH) / totalCollateralETH;
    }

    function sharesWorth(uint256 shares) public view returns (uint256) {
        return (currentUSDBalance() * shares) / s_totalDeposits;
    }

    function getTick() public view returns (int24) {
        (, int24 tick, , , , , ) = i_uniswapPool.slot0();
        return tick;
    }

    function getUsdcOraclePrice() public view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_usdcAddress) * PRECISION) / 1e8;
    }

    function getWethOraclePrice() public view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_wethAddress) * PRECISION) / 1e8;
    }

    function getWmaticOraclePrice() public view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_wmaticAddress) * PRECISION) / 1e8;
    }

    function _getPositionID() internal view returns (bytes32 positionID) {
        return
            keccak256(
                abi.encodePacked(address(this), s_lowerTick, s_upperTick)
            );
    }

    function calculateCurrentPositionReserves()
        public
        view
        returns (uint256 amount0Current, uint256 amount1Current)
    {
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = i_uniswapPool.slot0();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = i_uniswapPool.positions(_getPositionID());

        // compute current holdings from liquidity
        (amount0Current, amount1Current) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtRatioX96,
                s_lowerTick.getSqrtRatioAtTick(),
                s_upperTick.getSqrtRatioAtTick(),
                liquidity
            );

        // compute current fees earned
        uint256 fee0 = _computeFeesEarned(
            true,
            feeGrowthInside0Last,
            tick,
            liquidity
        ) + uint256(tokensOwed0);
        uint256 fee1 = _computeFeesEarned(
            false,
            feeGrowthInside1Last,
            tick,
            liquidity
        ) + uint256(tokensOwed1);

        /**TODO: add performance fee subtraction */
        //(fee0, fee1) = _subtractAdminFees(fee0, fee1);

        // add any leftover in contract to current holdings
        amount0Current +=
            fee0 +
            TransferHelper.safeGetBalance(i_wmaticAddress, address(this));
        amount1Current += fee1 + TransferHelper.safeGetBalance(i_wethAddress, address(this));

        return (amount0Current, amount1Current);
    }

    function _computeFeesEarned(
        bool isZero,
        uint256 feeGrowthInsideLast,
        int24 tick,
        uint128 liquidity
    ) private view returns (uint256 fee) {
        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
        if (isZero) {
            feeGrowthGlobal = i_uniswapPool.feeGrowthGlobal0X128();
            (, , feeGrowthOutsideLower, , , , , ) = i_uniswapPool.ticks(
                s_lowerTick
            );
            (, , feeGrowthOutsideUpper, , , , , ) = i_uniswapPool.ticks(
                s_upperTick
            );
        } else {
            feeGrowthGlobal = i_uniswapPool.feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = i_uniswapPool.ticks(
                s_lowerTick
            );
            (, , , feeGrowthOutsideUpper, , , , ) = i_uniswapPool.ticks(
                s_upperTick
            );
        }

        unchecked {
            // calculate fee growth below
            uint256 feeGrowthBelow;
            if (tick >= s_lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove;
            if (tick < s_upperTick) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }

            uint256 feeGrowthInside = feeGrowthGlobal -
                feeGrowthBelow -
                feeGrowthAbove;
            fee = FullMath.mulDiv(
                liquidity,
                feeGrowthInside - feeGrowthInsideLast,
                0x100000000000000000000000000000000
            );
        }
    }

    function getAUSDCTokenBalance() public view returns (uint256) {
        return i_aaveAUSDCToken.balanceOf(address(this));
    }

    function getVWETHTokenBalance() public view returns (uint256) {
        return i_aaveVWETHToken.scaledBalanceOf(address(this));
    }

    function getVWMATICTokenBalance() public view returns (uint256) {
        return i_aaveVWMATICToken.scaledBalanceOf(address(this));
    }

    function calculateVirtPoolReserves()
        internal
        view
        returns (uint256, uint256)
    {
        uint256 amount0;
        uint256 amount1;
        uint128 virtLiquidity = 1e18;
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            getTick().getSqrtRatioAtTick(),
            s_lowerTick.getSqrtRatioAtTick(),
            s_upperTick.getSqrtRatioAtTick(),
            virtLiquidity
        );
        return (amount0, amount1);
    }

    function calculateRealPoolReserves()
        internal
        view
        returns (uint256, uint256)
    {
        (uint128 liquidity, , , , ) = i_uniswapPool.positions(_getPositionID());

        // compute current holdings from liquidity
        (uint256 amount0Current, uint256 amount1Current) = LiquidityAmounts
            .getAmountsForLiquidity(
                getTick().getSqrtRatioAtTick(),
                s_lowerTick.getSqrtRatioAtTick(),
                s_upperTick.getSqrtRatioAtTick(),
                liquidity
            );

        return (amount0Current, amount1Current);
    }

    // =================================
    // Temporary solution for testing
    // =================================

    function giveAllApproves() public {
        TransferHelper.safeApprove(
            i_usdcAddress,
            address(i_aaveV3Pool),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_usdcAddress,
            address(i_uniswapSwapRouter),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_usdcAddress,
            address(i_uniswapPool),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_usdcAddress,
            address(i_aaveWTG3),
            type(uint256).max
        );

        TransferHelper.safeApprove(
            i_wethAddress,
            address(i_aaveV3Pool),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wethAddress,
            address(i_aaveWTG3),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            i_wethAddress,
            address(i_uniswapSwapRouter),
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
            i_wmaticAddress,
            address(i_aaveV3Pool),
            type(uint256).max
        );
    }
}