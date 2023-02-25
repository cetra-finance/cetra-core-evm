// SPDX-License-Identifier: MIT License
pragma solidity >=0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

import "./Uniswap/utils/LiquidityAmounts.sol";
import "./Uniswap/interfaces/ISwapRouter.sol";
import "./Uniswap/interfaces/IUniswapV3Pool.sol";
import "./Uniswap/interfaces/callback/IUniswapV3MintCallback.sol";

import "./AaveInterfaces/IPool.sol";
import "./AaveInterfaces/IAaveOracle.sol";
import "./AaveInterfaces/IAToken.sol";
import "./AaveInterfaces/IVariableDebtToken.sol";

import "./TransferHelper.sol";
import "./MathHelper.sol";

import "./IChamberV1.sol";

/*Errors */
error ChamberV1__ReenterancyGuard();
error ChamberV1__AaveDepositError();
error ChamberV1__UserRepaidMoreToken0ThanOwned();
error ChamberV1__UserRepaidMoreToken1ThanOwned();
error ChamberV1__SwappedUsdcForToken0StillCantRepay();
error ChamberV1__SwappedToken0ForToken1StillCantRepay();
error ChamberV1__CallerIsNotUniPool();
error ChamberV1__sharesWorthMoreThenDep();
error ChamberV1__TicksOut();
error ChamberV1__UpkeepNotNeeded(uint256 _currentLTV, uint256 _totalShares);

// For Wmatic/Weth
contract ChamberV1_LINKETH is
    IChamberV1,
    Ownable,
    IUniswapV3MintCallback,
    AutomationCompatibleInterface
{
    // =================================
    // Storage for users and their deposits
    // =================================

    uint256 private s_totalShares;
    mapping(address => uint256) private s_userShares;

    // =================================
    // Storage for pool
    // =================================

    int24 private s_lowerTick;
    int24 private s_upperTick;
    bool private s_liquidityTokenId;

    // =================================
    // Storage for logic
    // =================================

    bool private unlocked;

    uint256 private s_targetLTV;
    uint256 private s_minLTV;
    uint256 private s_maxLTV;
    uint256 private s_hedgeDev;

    uint256 private s_cetraFeeToken0;
    uint256 private s_cetraFeeToken1;

    int24 private s_ticksRange;

    address private immutable i_usdcAddress;
    address private immutable i_token0Address;
    address private immutable i_token1Address;

    IAToken private immutable i_aaveAUSDCToken;
    IVariableDebtToken private immutable i_aaveVToken0;
    IVariableDebtToken private immutable i_aaveVToken1;

    IAaveOracle private immutable i_aaveOracle;
    IPool private immutable i_aaveV3Pool;

    ISwapRouter private immutable i_uniswapSwapRouter;
    IUniswapV3Pool private immutable i_uniswapPool;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant CETRA_FEE = 5 * 1e16;

    // ================================
    // Modifiers
    // =================================

    modifier lock() {
        if (!unlocked) {
            revert ChamberV1__ReenterancyGuard();
        }
        unlocked = false;
        _;
        unlocked = true;
    }

    // =================================
    // Constructor
    // =================================

    constructor(
        address _uniswapSwapRouterAddress,
        address _uniswapPoolAddress,
        address _aaveV3poolAddress,
        address _aaveVTOKEN0Address,
        address _aaveVTOKEN1Address,
        address _aaveOracleAddress,
        address _aaveAUSDCAddress,
        int24 _ticksRange
    ) {
        i_uniswapSwapRouter = ISwapRouter(_uniswapSwapRouterAddress);
        i_uniswapPool = IUniswapV3Pool(_uniswapPoolAddress);
        i_aaveV3Pool = IPool(_aaveV3poolAddress);
        i_aaveOracle = IAaveOracle(_aaveOracleAddress);
        i_aaveAUSDCToken = IAToken(_aaveAUSDCAddress);
        i_aaveVToken0 = IVariableDebtToken(_aaveVTOKEN0Address);
        i_aaveVToken1 = IVariableDebtToken(_aaveVTOKEN1Address);
        i_usdcAddress = i_aaveAUSDCToken.UNDERLYING_ASSET_ADDRESS();
        i_token0Address = i_aaveVToken0.UNDERLYING_ASSET_ADDRESS();
        i_token1Address = i_aaveVToken1.UNDERLYING_ASSET_ADDRESS();
        unlocked = true;
        s_ticksRange = _ticksRange;
    }

    // =================================
    // Main funcitons
    // =================================

    function mint(uint256 usdAmount) external override lock {
        {
            uint256 currUsdBalance = currentUSDBalance();
            uint256 sharesToMint = (currUsdBalance > 10)
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
        _mint(usdAmount);
    }

    function burn(uint256 _shares) external override lock {
        uint256 usdcBalanceBefore = TransferHelper.safeGetBalance(
            i_usdcAddress
        );
        _burn(_shares);

        s_totalShares -= _shares;
        s_userShares[msg.sender] -= _shares;

        TransferHelper.safeTransfer(
            i_usdcAddress,
            msg.sender,
            TransferHelper.safeGetBalance(i_usdcAddress) - usdcBalanceBefore
        );
    }

    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        uint256 _currentLTV = currentLTV();
        (
            uint256 token0Pool,
            uint256 token1Pool
        ) = calculateCurrentPoolReserves();
        uint256 token0Borrowed = getVToken0Balance();
        uint256 token1Borrowed = getVToken1Balance();
        bool tooMuchExposureTakenToken0;
        bool tooMuchExposureTakenToken1;
        if (token1Pool == 0 || token0Pool == 0) {
            tooMuchExposureTakenToken0 = true;
            tooMuchExposureTakenToken1 = true;
        } else {
            tooMuchExposureTakenToken0 = (token0Borrowed > token0Pool)
                ? (((token0Borrowed - token0Pool) * PRECISION) / token0Pool >
                    s_hedgeDev)
                : (
                    (((token0Pool - token0Borrowed) * PRECISION) / token0Pool >
                        s_hedgeDev)
                );
            tooMuchExposureTakenToken1 = (token1Borrowed > token1Pool)
                ? (((token1Borrowed - token1Pool) * PRECISION) / token1Pool >
                    s_hedgeDev)
                : (
                    (((token1Pool - token1Borrowed) * PRECISION) / token1Pool >
                        s_hedgeDev)
                );
        }
        upkeepNeeded =
            (_currentLTV >= s_maxLTV ||
                _currentLTV <= s_minLTV ||
                tooMuchExposureTakenToken0 ||
                tooMuchExposureTakenToken1) &&
            (s_totalShares != 0);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert ChamberV1__UpkeepNotNeeded(currentLTV(), s_totalShares);
        }
        rebalance();
    }

    // =================================
    // Main funcitons helpers
    // =================================

    function _mint(uint256 usdAmount) private {
        uint256 amount0;
        uint256 amount1;
        uint256 usedLTV;

        int24 currentTick = getTick();

        if (!s_liquidityTokenId) {
            s_lowerTick = ((currentTick - s_ticksRange) / 60) * 60;
            s_upperTick = ((currentTick + s_ticksRange) / 60) * 60;
            usedLTV = s_targetLTV;
            s_liquidityTokenId = true;
        } else {
            usedLTV = currentLTV();
        }
        if (usedLTV < (10 * PRECISION) / 100) {
            usedLTV = s_targetLTV;
        }
        (amount0, amount1) = calculatePoolReserves(uint128(1e18));

        i_aaveV3Pool.supply(
            i_usdcAddress,
            TransferHelper.safeGetBalance(i_usdcAddress),
            address(this),
            0
        );

        uint256 usdcOraclePrice = getUsdcOraclePrice();
        uint256 token0OraclePrice = getToken0OraclePrice();
        uint256 token1OraclePrice = getToken1OraclePrice();

        if (amount0 == 0 || amount1 == 0) {
            revert ChamberV1__TicksOut();
        }

        uint256 token0ToBorrow = (usdAmount * usdcOraclePrice * usedLTV) /
            (token0OraclePrice /
                1e12 +
                (token1OraclePrice * amount1) /
                amount0 /
                1e12) /
            PRECISION;

        uint256 token1ToBorrow = (usdAmount * usdcOraclePrice * usedLTV) /
            ((token0OraclePrice * amount0) /
                amount1 /
                1e12 +
                token1OraclePrice /
                1e12) /
            PRECISION;

        if (token0ToBorrow > 0) {
            i_aaveV3Pool.borrow(
                i_token0Address,
                token0ToBorrow,
                2,
                0,
                address(this)
            );
        }
        if (token1ToBorrow > 0) {
            i_aaveV3Pool.borrow(
                i_token1Address,
                token1ToBorrow,
                2,
                0,
                address(this)
            );
        }

        {
            uint256 token0Recieved = TransferHelper.safeGetBalance(
                i_token0Address
            ) - s_cetraFeeToken0;
            uint256 token1Recieved = TransferHelper.safeGetBalance(
                i_token1Address
            ) - s_cetraFeeToken1;

            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                getSqrtRatioX96(),
                MathHelper.getSqrtRatioAtTick(s_lowerTick),
                MathHelper.getSqrtRatioAtTick(s_upperTick),
                token0Recieved,
                token1Recieved
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

    function _burn(uint256 _shares) private {
        (
            uint256 burnToken0,
            uint256 burnToken1,
            uint256 feeToken0,
            uint256 feeToken1
        ) = _withdraw(uint128((getLiquidity() * _shares) / s_totalShares));
        _applyFees(feeToken0, feeToken1);

        uint256 amountToken0 = burnToken0 +
            ((TransferHelper.safeGetBalance(i_token0Address) -
                burnToken0 -
                s_cetraFeeToken0) * _shares) /
            s_totalShares;
        uint256 amountToken1 = burnToken1 +
            ((TransferHelper.safeGetBalance(i_token1Address) -
                burnToken1 -
                s_cetraFeeToken1) * _shares) /
            s_totalShares;

        {
            (
                uint256 token0Remainder,
                uint256 token1Remainder
            ) = _repayAndWithdraw(_shares, amountToken0, amountToken1);
            if (token0Remainder > 0) {
                swapExactAssetToStable(i_token0Address, token0Remainder);
            }
            if (token1Remainder > 0) {
                swapExactAssetToStable(i_token1Address, token1Remainder);
            }
        }
    }

    function rebalance() private {
        s_liquidityTokenId = false;
        _burn(s_totalShares);
        _mint(TransferHelper.safeGetBalance(i_usdcAddress));
    }

    // =================================
    // Private funcitons
    // =================================

    function _repayAndWithdraw(
        uint256 _shares,
        uint256 token0OwnedByUser,
        uint256 token1OwnedByUser
    ) private returns (uint256, uint256) {
        uint256 token1DebtToCover = (getVToken1Balance() * _shares) /
            s_totalShares;
        uint256 token0DebtToCover = (getVToken0Balance() * _shares) /
            s_totalShares;
        uint256 token1BalanceBefore = TransferHelper.safeGetBalance(
            i_token1Address
        );
        uint256 token0BalanceBefore = TransferHelper.safeGetBalance(
            i_token0Address
        );
        uint256 token1Remainder;
        uint256 token0Remainder;

        uint256 token0Swapped = 0;
        uint256 usdcSwapped = 0;

        uint256 _currentLTV = currentLTV();
        if (token1OwnedByUser < token1DebtToCover) {
            token0Swapped += swapAssetToExactAsset(
                i_token0Address,
                i_token1Address,
                token1DebtToCover - token1OwnedByUser
            );
            if (
                token1OwnedByUser +
                    TransferHelper.safeGetBalance(i_token1Address) -
                    token1BalanceBefore <
                token1DebtToCover
            ) {
                revert ChamberV1__SwappedToken0ForToken1StillCantRepay();
            }
        }
        i_aaveV3Pool.repay(
            i_token1Address,
            token1DebtToCover,
            2,
            address(this)
        );
        if (
            TransferHelper.safeGetBalance(i_token1Address) >=
            token1BalanceBefore - token1OwnedByUser
        ) {
            token1Remainder =
                TransferHelper.safeGetBalance(i_token1Address) +
                token1OwnedByUser -
                token1BalanceBefore;
        } else {
            revert ChamberV1__UserRepaidMoreToken1ThanOwned();
        }

        i_aaveV3Pool.withdraw(
            i_usdcAddress,
            (((1e6 * token1DebtToCover * getToken1OraclePrice()) /
                getUsdcOraclePrice()) / _currentLTV),
            address(this)
        );

        if (token0OwnedByUser < token0DebtToCover + token0Swapped) {
            usdcSwapped += swapStableToExactAsset(
                i_token0Address,
                token0DebtToCover + token0Swapped - token0OwnedByUser
            );
            if (
                (token0OwnedByUser +
                    TransferHelper.safeGetBalance(i_token0Address)) -
                    token0BalanceBefore <
                token0DebtToCover
            ) {
                revert ChamberV1__SwappedUsdcForToken0StillCantRepay();
            }
        }

        i_aaveV3Pool.repay(
            i_token0Address,
            token0DebtToCover,
            2,
            address(this)
        );

        if (
            TransferHelper.safeGetBalance(i_token0Address) >=
            token0BalanceBefore - token0OwnedByUser
        ) {
            token0Remainder =
                TransferHelper.safeGetBalance(i_token0Address) +
                token0OwnedByUser -
                token0BalanceBefore;
        } else {
            revert ChamberV1__UserRepaidMoreToken0ThanOwned();
        }

        i_aaveV3Pool.withdraw(
            i_usdcAddress,
            (((1e6 * token0DebtToCover * getToken0OraclePrice()) /
                getUsdcOraclePrice()) / _currentLTV),
            address(this)
        );

        return (token0Remainder, token1Remainder);
    }

    function swapExactAssetToStable(
        address assetIn,
        uint256 amountIn
    ) private returns (uint256) {
        uint256 amountOut = i_uniswapSwapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(assetIn, uint24(3000), i_usdcAddress),
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
        uint256 amountOut
    ) private returns (uint256) {
        uint256 amountIn = i_uniswapSwapRouter.exactOutput(
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(assetOut, uint24(3000), i_usdcAddress),
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: 1e50
            })
        );
        return (amountIn);
    }

    function swapAssetToExactAsset(
        address assetIn,
        address assetOut,
        uint256 amountOut
    ) private returns (uint256) {
        uint256 amountIn = i_uniswapSwapRouter.exactOutput(
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(
                    assetOut,
                    uint24(3000),
                    i_usdcAddress,
                    uint24(3000),
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
    ) private returns (uint256, uint256, uint256, uint256) {
        uint256 preBalanceToken1 = TransferHelper.safeGetBalance(
            i_token1Address
        );
        uint256 preBalanceToken0 = TransferHelper.safeGetBalance(
            i_token0Address
        );
        (uint256 burnToken0, uint256 burnToken1) = i_uniswapPool.burn(
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
        uint256 feeToken1 = TransferHelper.safeGetBalance(i_token1Address) -
            preBalanceToken1 -
            burnToken1;
        uint256 feeToken0 = TransferHelper.safeGetBalance(i_token0Address) -
            preBalanceToken0 -
            burnToken0;
        return (burnToken0, burnToken1, feeToken0, feeToken1);
    }

    function _applyFees(uint256 _feeToken0, uint256 _feeToken1) private {
        s_cetraFeeToken0 += (_feeToken0 * CETRA_FEE) / PRECISION;
        s_cetraFeeToken1 += (_feeToken1 * CETRA_FEE) / PRECISION;
    }

    // =================================
    // View funcitons
    // =================================

    function getAdminBalance()
        external
        view
        override
        returns (uint256, uint256)
    {
        return (s_cetraFeeToken0, s_cetraFeeToken1);
    }

    function currentUSDBalance() public view override returns (uint256) {
        (
            uint256 token0PoolBalance,
            uint256 token1PoolBalance
        ) = calculateCurrentPoolReserves();
        (
            uint256 token0FeePending,
            uint256 token1FeePending
        ) = calculateCurrentFees();
        uint256 pureUSDCAmount = getAUSDCTokenBalance() +
            TransferHelper.safeGetBalance(i_usdcAddress);
        uint256 poolTokensValue = ((token0PoolBalance +
            token0FeePending +
            TransferHelper.safeGetBalance(i_token0Address) -
            s_cetraFeeToken0) *
            getToken0OraclePrice() +
            (token1PoolBalance +
                token1FeePending +
                TransferHelper.safeGetBalance(i_token1Address) -
                s_cetraFeeToken1) *
            getToken1OraclePrice()) /
            getUsdcOraclePrice() /
            1e12;
        uint256 debtTokensValue = (getVToken0Balance() *
            getToken0OraclePrice() +
            getVToken1Balance() *
            getToken1OraclePrice()) /
            getUsdcOraclePrice() /
            1e12;
        return pureUSDCAmount + poolTokensValue - debtTokensValue;
    }

    function currentLTV() public view override returns (uint256) {
        // return currentETHBorrowed * getToken0OraclePrice() / currentUSDInCollateral/getUsdOraclePrice()
        (
            uint256 totalCollateralETH,
            uint256 totalBorrowedETH,
            ,
            ,
            ,

        ) = i_aaveV3Pool.getUserAccountData(address(this));
        uint256 ltv = totalCollateralETH == 0
            ? 0
            : (PRECISION * totalBorrowedETH) / totalCollateralETH;
        return ltv;
    }

    function sharesWorth(uint256 shares) private view returns (uint256) {
        return (currentUSDBalance() * shares) / s_totalShares;
    }

    function getTick() private view returns (int24) {
        (, int24 tick, , , , , ) = i_uniswapPool.slot0();
        return tick;
    }

    function getUsdcOraclePrice() private view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_usdcAddress) * 1e10);
    }

    function getToken0OraclePrice() private view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_token0Address) * 1e10);
    }

    function getToken1OraclePrice() private view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_token1Address) * 1e10);
    }

    function _getPositionID() private view returns (bytes32 positionID) {
        return
            keccak256(
                abi.encodePacked(address(this), s_lowerTick, s_upperTick)
            );
    }

    function getSqrtRatioX96() private view returns (uint160) {
        (uint160 sqrtRatioX96, , , , , , ) = i_uniswapPool.slot0();
        return sqrtRatioX96;
    }

    function calculatePoolReserves(
        uint128 liquidity
    ) private view returns (uint256, uint256) {
        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                getSqrtRatioX96(),
                MathHelper.getSqrtRatioAtTick(s_lowerTick),
                MathHelper.getSqrtRatioAtTick(s_upperTick),
                liquidity
            );
        return (amount0, amount1);
    }

    function calculateCurrentPoolReserves()
        public
        view
        override
        returns (uint256, uint256)
    {
        // compute current holdings from liquidity
        (uint256 amount0Current, uint256 amount1Current) = LiquidityAmounts
            .getAmountsForLiquidity(
                getSqrtRatioX96(),
                MathHelper.getSqrtRatioAtTick(s_lowerTick),
                MathHelper.getSqrtRatioAtTick(s_upperTick),
                getLiquidity()
            );

        return (amount0Current, amount1Current);
    }

    function getLiquidity() private view returns (uint128) {
        (uint128 liquidity, , , , ) = i_uniswapPool.positions(_getPositionID());
        return liquidity;
    }

    function calculateCurrentFees()
        private
        view
        returns (uint256 fee0, uint256 fee1)
    {
        int24 tick = getTick();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = i_uniswapPool.positions(_getPositionID());
        fee0 =
            _computeFeesEarned(true, feeGrowthInside0Last, tick, liquidity) +
            uint256(tokensOwed0);

        fee1 =
            _computeFeesEarned(false, feeGrowthInside1Last, tick, liquidity) +
            uint256(tokensOwed1);
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

    function getAUSDCTokenBalance() private view returns (uint256) {
        return i_aaveAUSDCToken.balanceOf(address(this));
    }

    function getVToken0Balance() private view returns (uint256) {
        return
            (i_aaveVToken0.scaledBalanceOf(address(this)) *
                i_aaveV3Pool.getReserveNormalizedVariableDebt(
                    i_token0Address
                )) / 1e27;
    }

    function getVToken1Balance() private view returns (uint256) {
        return
            (i_aaveVToken1.scaledBalanceOf(address(this)) *
                i_aaveV3Pool.getReserveNormalizedVariableDebt(
                    i_token1Address
                )) / 1e27;
    }

    // =================================
    // Getters
    // =================================

    function get_i_aaveVToken0() external view override returns (address) {
        return address(i_aaveVToken0);
    }

    function get_i_aaveVToken1() external view override returns (address) {
        return address(i_aaveVToken1);
    }

    function get_i_aaveAUSDCToken() external view override returns (address) {
        return address(i_aaveAUSDCToken);
    }

    function get_s_totalShares() external view override returns (uint256) {
        return s_totalShares;
    }

    function get_s_userShares(
        address user
    ) external view override returns (uint256) {
        return s_userShares[user];
    }

    // =================================
    // Callbacks
    // =================================

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
                i_token0Address,
                msg.sender,
                amount0Owed
            );
        if (amount1Owed > 0)
            TransferHelper.safeTransfer(
                i_token1Address,
                msg.sender,
                amount1Owed
            );
    }

    receive() external payable {}

    // =================================
    // Admin functions
    // =================================

    function _redeemFees() external override onlyOwner {
        TransferHelper.safeTransfer(i_token1Address, owner(), s_cetraFeeToken1);
        TransferHelper.safeTransfer(i_token0Address, owner(), s_cetraFeeToken0);
        s_cetraFeeToken1 = 0;
        s_cetraFeeToken0 = 0;
    }

    function setTicksRange(int24 _ticksRange) external override onlyOwner {
        s_ticksRange = _ticksRange;
    }

    function giveApprove(
        address _token,
        address _to
    ) external override onlyOwner {
        TransferHelper.safeApprove(_token, _to, type(uint256).max);
    }

    function setLTV(
        uint256 _targetLTV,
        uint256 _minLTV,
        uint256 _maxLTV,
        uint256 _hedgeDev
    ) external override onlyOwner {
        s_targetLTV = _targetLTV;
        s_minLTV = _minLTV;
        s_maxLTV = _maxLTV;
        s_hedgeDev = _hedgeDev;
    }
}
