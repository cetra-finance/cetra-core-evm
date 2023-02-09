// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
pragma abicoder v2;

import "./Uniswap/utils/LiquidityAmounts.sol";
import "./Uniswap/interfaces/ISwapRouter.sol";
import "./Uniswap/interfaces/IUniswapV3Pool.sol";
import "./Uniswap/interfaces/callback/IUniswapV3MintCallback.sol";

import "./AaveInterfaces/IPool.sol";
import "./AaveInterfaces/aaveIWETHGateway.sol";
import "./AaveInterfaces/IAaveOracle.sol";
import "./AaveInterfaces/IAToken.sol";
import "./AaveInterfaces/IVariableDebtToken.sol";

import "./TransferHelper.sol";
import "./MathHelper.sol";

import "hardhat/console.sol";

/*Errors */
error ChamberV1__AaveDepositError();
error ChamberV1__SwappedWethForWmaticStillCantRepay();
error ChamberV1__SwappedWmaticForWethStillCantRepay();
error ChamberV1__SwappedUsdcForWethStillCantRepay();
error ChamberV1__CallerIsNotUniPool();
error ChamberV1__sharesWorthMoreThenDep();

contract ChamberV1 is IUniswapV3MintCallback {
    // =================================
    // Storage for users and their deposits
    // =================================

    uint256 public s_totalShares;
    mapping(address => uint256) public s_userShares;

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

    ISwapRouter private immutable i_uniswapSwapRouter;
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
        address _aaveAUSDCAddress //uint256 _targetLTV
    ) {
        i_uniswapSwapRouter = ISwapRouter(_uniswapSwapRouterAddress);
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
        if (msg.sender != address(i_uniswapPool)) {
            revert ChamberV1__CallerIsNotUniPool();
        }

        if (amount0Owed > 0)
            TransferHelper.safeTransfer(
                i_wmaticAddress,
                msg.sender,
                amount0Owed
            );
        if (amount1Owed > 0)
            TransferHelper.safeTransfer(i_wethAddress, msg.sender, amount1Owed);
    }

    // =================================
    // Main funciton
    // =================================

    function mint(uint256 usdAmount) external {
        {
            uint256 currUsdBalance = currentUSDBalance();
            console.log("currUsdBalance", currUsdBalance);
            uint256 sharesToMint = (currUsdBalance != 0)
                ? ((usdAmount * s_totalShares) / (currUsdBalance))
                : usdAmount;
            s_totalShares += sharesToMint;
            s_userShares[msg.sender] += sharesToMint;
            if (sharesWorth(sharesToMint) >= usdAmount) {
                revert ChamberV1__sharesWorthMoreThenDep();
            }
            TransferHelper.safeTransferFrom(
                i_usdcAddress,
                msg.sender,
                address(this),
                usdAmount
            );
        }

        uint256 amount0;
        uint256 amount1;
        uint256 usedLTV;

        int24 currentTick = getTick();

        if (!s_liquidityTokenId) {
            s_lowerTick = ((currentTick - 400) / 10) * 10;
            s_upperTick = ((currentTick + 400) / 10) * 10;
            (amount0, amount1) = calculateVirtPoolReserves(currentTick);
            usedLTV = s_targetLTV;
            s_liquidityTokenId = true;
        } else {
            usedLTV = currentLTV();
            (amount0, amount1) = calculateRealPoolReserves(currentTick);
        }

        i_aaveV3Pool.supply(
            i_usdcAddress,
            TransferHelper.safeGetBalance(i_usdcAddress, address(this)),
            address(this),
            0
        );

        uint256 usdcOraclePrice = getUsdcOraclePrice();
        uint256 wmaticOraclePrice = getWmaticOraclePrice();
        uint256 wethOraclePrice = getWethOraclePrice();

        uint256 wethToBorrow = (usdAmount * usdcOraclePrice * usedLTV) /
            ((wmaticOraclePrice * amount0) /
                amount1 /
                1e12 +
                wethOraclePrice /
                1e12) /
            PRECISION;

        uint256 wmaticToBorrow = (usdAmount * usdcOraclePrice * usedLTV) /
            (wmaticOraclePrice /
                1e12 +
                (wethOraclePrice * amount1) /
                amount0 /
                1e12) /
            PRECISION;

        i_aaveV3Pool.borrow(
            i_wmaticAddress,
            wmaticToBorrow,
            2,
            0,
            address(this)
        );

        i_aaveV3Pool.borrow(i_wethAddress, wethToBorrow, 2, 0, address(this));

        {
            uint256 wmaticRecieved = TransferHelper.safeGetBalance(
                i_wmaticAddress,
                address(this)
            );
            uint256 wethRecieved = TransferHelper.safeGetBalance(
                i_wethAddress,
                address(this)
            );
            (uint160 sqrtRatioX96, , , , , , ) = i_uniswapPool.slot0();
            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                MathHelper.getSqrtRatioAtTick(s_lowerTick),
                MathHelper.getSqrtRatioAtTick(s_upperTick),
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

    function burn(uint256 _shares) external {
        uint256 usdcToReturn = 0;

        (
            uint256 burnWMATIC,
            uint256 burnWETH,
            uint256 feeWMATIC,
            uint256 feeWETH
        ) = _withdraw(
                uint128((getPositionLiquidity() * _shares) / s_totalShares)
            );

        uint256 amountWmatic = burnWMATIC +
            ((TransferHelper.safeGetBalance(i_wmaticAddress, address(this)) -
                burnWMATIC) * _shares) /
            s_totalShares;
        uint256 amountWeth = burnWETH +
            ((TransferHelper.safeGetBalance(i_wethAddress, address(this)) -
                burnWETH) * _shares) /
            s_totalShares;
        uint256 usdcBalanceBefore = TransferHelper.safeGetBalance(
            i_usdcAddress,
            address(this)
        );
        {
            (
                uint256 wmaticRemainder,
                uint256 wethRemainder
            ) = _repayAndWithdraw(_shares, amountWmatic, amountWeth);
            if (wmaticRemainder > 0) {
                usdcToReturn += swapExactAssetToStable(
                    i_wmaticAddress,
                    i_wethAddress,
                    wmaticRemainder
                );
            }
            if (wethRemainder > 0) {
                usdcToReturn += swapExactAssetToStable(
                    i_wethAddress,
                    i_wmaticAddress,
                    wethRemainder
                );
            }
        }

        s_totalShares -= _shares;
        s_userShares[msg.sender] -= _shares;

        TransferHelper.safeTransfer(
            i_usdcAddress,
            msg.sender,
            TransferHelper.safeGetBalance(i_usdcAddress, address(this)) -
                usdcBalanceBefore
        );
    }

    function _repayAndWithdraw(
        uint256 _shares,
        uint256 wmaticOwnedByUser,
        uint256 wethOwnedByUser
    ) internal returns (uint256, uint256) {
        uint256 wmaticDebtToCover = (getVWMATICTokenBalance() * _shares) /
            s_totalShares;
        uint256 wethDebtToCover = (getVWETHTokenBalance() * _shares) /
            s_totalShares;
        uint256 wmaticBalanceBefore = TransferHelper.safeGetBalance(
            i_wmaticAddress,
            address(this)
        );
        uint256 wethBalanceBefore = TransferHelper.safeGetBalance(
            i_wethAddress,
            address(this)
        );
        uint256 wmaticRemainder;
        uint256 wethRemainder;

        uint256 wethSwapped = 0;
        uint256 usdcSwapped = 0;

        uint256 _currentLTV = currentLTV();

        if (wmaticOwnedByUser < wmaticDebtToCover) {
            wethSwapped += swapAssetToExactAsset(
                i_wethAddress,
                i_wmaticAddress,
                wmaticDebtToCover - wmaticOwnedByUser
            );
            if (
                wmaticOwnedByUser +
                    TransferHelper.safeGetBalance(
                        i_wmaticAddress,
                        address(this)
                    ) -
                    wmaticBalanceBefore <
                wmaticDebtToCover
            ) {
                revert ChamberV1__SwappedWethForWmaticStillCantRepay();
            } else {
                console.log("wmaticDebtToCover", wmaticDebtToCover);
                i_aaveV3Pool.repay(
                    i_wmaticAddress,
                    wmaticDebtToCover,
                    2,
                    address(this)
                );
                // no dust should be remaining
                // uint256 wmaticUserRemainder = wmaticOwnedByUser +
                //     IERC20(i_wmaticAddress).balanceOf(address(this)) -
                //     wmaticBalanceBefore -
                //     wmaticDebtToCover;
            }
            wmaticRemainder = 0;
        } else {
            console.log("wmaticDebtToCover", wmaticDebtToCover);
            i_aaveV3Pool.repay(
                i_wmaticAddress,
                wmaticDebtToCover,
                2,
                address(this)
            );
            wmaticRemainder = wmaticOwnedByUser - wmaticDebtToCover;
        }

        console.log(
            (((1e6 * wmaticDebtToCover * getWmaticOraclePrice()) /
                getUsdcOraclePrice()) / _currentLTV)
        );

        i_aaveV3Pool.withdraw(
            i_usdcAddress,
            (((1e6 * wmaticDebtToCover * getWmaticOraclePrice()) /
                getUsdcOraclePrice()) / _currentLTV),
            address(this)
        );
        console.log(
            TransferHelper.safeGetBalance(i_usdcAddress, address(this))
        );

        if (wethOwnedByUser + 1e12 < wethDebtToCover + wethSwapped) {
            console.log((wethDebtToCover + wethSwapped - wethOwnedByUser));
            usdcSwapped += swapStableToExactAsset(
                i_wethAddress,
                i_wmaticAddress,
                wethDebtToCover + wethSwapped - wethOwnedByUser
            );
            if (
                wethOwnedByUser +
                    (TransferHelper.safeGetBalance(
                        i_wethAddress,
                        address(this)
                    ) - wethBalanceBefore) <
                wethDebtToCover
            ) {
                revert ChamberV1__SwappedUsdcForWethStillCantRepay();
            } else {
                console.log("wethDebtToCover", wethDebtToCover);
                i_aaveV3Pool.repay(
                    i_wethAddress,
                    wethDebtToCover,
                    2,
                    address(this)
                );
                // no dust should be remaining
                // uint256 wmaticUserRemainder = wmaticOwnedByUser +
                //     IERC20(i_wmaticAddress).balanceOf(address(this)) -
                //     wmaticBalanceBefore -
                //     wmaticDebtToCover;
            }
            wethRemainder = 0;
        } else {
            console.log("wethDebtToCover", wethDebtToCover);
            i_aaveV3Pool.repay(
                i_wethAddress,
                wethDebtToCover,
                2,
                address(this)
            );
            wethRemainder = wethOwnedByUser - wethDebtToCover;
        }

        i_aaveV3Pool.withdraw(
            i_usdcAddress,
            (((1e6 * wethDebtToCover * getWethOraclePrice()) /
                getUsdcOraclePrice()) / _currentLTV),
            address(this)
        );

        return (wmaticRemainder, wethRemainder);
    }

    function swapExactAssetToStable(
        address assetIn,
        address assetOther,
        uint256 amountIn
    ) internal returns (uint256) {
        uint256 amountOut = i_uniswapSwapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(
                    assetIn,
                    uint24(500),
                    assetOther,
                    uint24(500),
                    i_usdcAddress
                ),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0
            })
        );
        return (amountOut);
    }

    function swapStableToExactAsset(
        address assetOut,
        address assetOther,
        uint256 amountOut
    ) internal returns (uint256) {
        uint256 amountIn = i_uniswapSwapRouter.exactOutput(
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(
                    i_usdcAddress,
                    uint24(500),
                    assetOther,
                    uint24(500),
                    assetOut
                ),
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: type(uint256).max
            })
        );
        return (amountIn);
    }

    function swapAssetToExactAsset(
        address assetIn,
        address assetOut,
        uint256 amountOut
    ) internal returns (uint256) {
        uint256 amountIn = i_uniswapSwapRouter.exactOutput(
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(
                    assetOut,
                    uint24(500),
                    i_usdcAddress,
                    uint24(500),
                    assetIn
                ),
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: type(uint256).max
            })
        );

        return (amountIn);
    }

    function _withdraw(
        uint128 liquidityToBurn
    ) internal returns (uint256, uint256, uint256, uint256) {
        uint256 preBalanceWMATIC = TransferHelper.safeGetBalance(
            i_wmaticAddress,
            address(this)
        );
        uint256 preBalanceWETH = TransferHelper.safeGetBalance(
            i_wethAddress,
            address(this)
        );

        (uint256 burnWMATIC, uint256 burnWETH) = i_uniswapPool.burn(
            s_lowerTick,
            s_upperTick,
            liquidityToBurn
        );
        i_uniswapPool.collect(
            address(this),
            s_lowerTick,
            s_upperTick,
            type(uint128).max,
            type(uint128).max
        );
        uint256 feeWMATIC = TransferHelper.safeGetBalance(
            i_wmaticAddress,
            address(this)
        ) -
            preBalanceWMATIC -
            burnWMATIC;
        uint256 feeWETH = TransferHelper.safeGetBalance(
            i_wethAddress,
            address(this)
        ) -
            preBalanceWETH -
            burnWETH;

        return (burnWMATIC, burnWETH, feeWMATIC, feeWETH);
    }

    function rebalance() external {}

    // =================================
    // FallBack
    // =================================

    receive() external payable {}

    // =================================
    // View funcitons
    // =================================

    function currentUSDBalance() public view returns (uint256) {
        (
            uint256 wmaticFee,
            uint256 wethFee
        ) = calculateCurrentPositionReserves();

        uint256 pureUSDCAmount = getAUSDCTokenBalance() +
            TransferHelper.safeGetBalance(i_usdcAddress, address(this));

        return (
            wethPoolBalance *
                getWethOraclePrice() +
                wmaticPoolBalance *
                getWmaticOraclePrice() >
                getVWETHTokenBalance() *
                    getWethOraclePrice() +
                    getVWMATICTokenBalance() *
                    getWmaticOraclePrice()
                ? pureUSDCAmount +
                    (((wethPoolBalance *
                        getWethOraclePrice() +
                        wmaticPoolBalance *
                        getWmaticOraclePrice()) -
                        (getVWETHTokenBalance() *
                            getWethOraclePrice() +
                            getVWMATICTokenBalance() *
                            getWmaticOraclePrice())) / getUsdcOraclePrice()) /
                    1e12
                : pureUSDCAmount -
                    (((getVWETHTokenBalance() *
                        getWethOraclePrice() +
                        getVWMATICTokenBalance() *
                        getWmaticOraclePrice()) -
                        (wethPoolBalance *
                            getWethOraclePrice() +
                            wmaticPoolBalance *
                            getWmaticOraclePrice())) / getUsdcOraclePrice()) /
                    1e12
        );
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
        return (currentUSDBalance() * shares) / s_totalShares;
    }

    function getTick() public view returns (int24) {
        (, int24 tick, , , , , ) = i_uniswapPool.slot0();
        return tick;
    }

    function getUsdcOraclePrice() public view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_usdcAddress) * 1e10);
    }

    function getWethOraclePrice() public view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_wethAddress) * 1e10);
    }

    function getWmaticOraclePrice() public view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_wmaticAddress) * 1e10);
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
                MathHelper.getSqrtRatioAtTick(s_lowerTick),
                MathHelper.getSqrtRatioAtTick(s_upperTick),
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

        return (fee0, fee1);
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
        return
            (i_aaveVWETHToken.scaledBalanceOf(address(this)) *
                i_aaveV3Pool.getReserveNormalizedVariableDebt(i_wethAddress)) /
            1e27;
    }

    function getVWMATICTokenBalance() public view returns (uint256) {
        return
            (i_aaveVWMATICToken.scaledBalanceOf(address(this)) *
                i_aaveV3Pool.getReserveNormalizedVariableDebt(
                    i_wmaticAddress
                )) / 1e27;
    }

    function getPositionLiquidity() public view returns (uint128) {
        (uint128 liquidity, , , , ) = i_uniswapPool.positions(_getPositionID());
        return liquidity;
    }

    function calculateVirtPoolReserves(
        int24 _currentTick
    ) internal view returns (uint256, uint256) {
        uint256 amount0;
        uint256 amount1;
        uint128 virtLiquidity = 1e18;
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            MathHelper.getSqrtRatioAtTick(_currentTick),
            MathHelper.getSqrtRatioAtTick(s_lowerTick),
            MathHelper.getSqrtRatioAtTick(s_upperTick),
            virtLiquidity
        );
        return (amount0, amount1);
    }

    function calculateRealPoolReserves(
        int24 _currentTick
    ) internal view returns (uint256, uint256) {
        // compute current holdings from liquidity
        (uint256 amount0Current, uint256 amount1Current) = LiquidityAmounts
            .getAmountsForLiquidity(
                MathHelper.getSqrtRatioAtTick(_currentTick),
                MathHelper.getSqrtRatioAtTick(s_lowerTick),
                MathHelper.getSqrtRatioAtTick(s_upperTick),
                getPositionLiquidity()
            );

        return (amount0Current, amount1Current);
    }

    // =================================
    // Temporary solution for testing
    // =================================

    function giveApprove(address _token, address _to) public {
        TransferHelper.safeApprove(_token, _to, type(uint256).max);
    }
}
