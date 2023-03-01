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

import "./IChamberV1Stable.sol";

import "hardhat/console.sol";

/*Errors */
error ChamberV1__ReenterancyGuard();
error ChamberV1__AaveDepositError();
error ChamberV1__UserRepaidMoreToken0ThanOwned();
error ChamberV1__UserRepaidMoreToken1ThanOwned();
error ChamberV1__SwappedUsdForToken0StillCantRepay();
error ChamberV1__SwappedToken0ForToken1StillCantRepay();
error ChamberV1__CallerIsNotUniPool();
error ChamberV1__sharesWorthMoreThenDep();
error ChamberV1__TicksOut();
error ChamberV1__UpkeepNotNeeded(uint256 _currentLTV, uint256 _totalShares);

// For Wmatic/Weth
contract ChamberV1Stable is
    IChamberV1Stable,
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

    uint256 private s_cetraFeeUsd;
    uint256 private s_cetraFeeToken;

    int24 private s_ticksRange;

    address private immutable i_usdAddress;
    address private immutable i_tokenAddress;

    IAToken private immutable i_aaveAUSDToken;
    IVariableDebtToken private immutable i_aaveVToken;

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
        address _aaveVTOKENAddress,
        address _aaveOracleAddress,
        address _aaveAUSDAddress,
        int24 _ticksRange
    ) {
        i_uniswapSwapRouter = ISwapRouter(_uniswapSwapRouterAddress);
        i_uniswapPool = IUniswapV3Pool(_uniswapPoolAddress);
        i_aaveV3Pool = IPool(_aaveV3poolAddress);
        i_aaveOracle = IAaveOracle(_aaveOracleAddress);
        i_aaveAUSDToken = IAToken(_aaveAUSDAddress);
        i_aaveVToken = IVariableDebtToken(_aaveVTOKENAddress);
        i_usdAddress = i_aaveAUSDToken.UNDERLYING_ASSET_ADDRESS();
        i_tokenAddress = i_aaveVToken.UNDERLYING_ASSET_ADDRESS();
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
                i_usdAddress,
                msg.sender,
                address(this),
                usdAmount
            );
        }
        _mint(usdAmount);
    }

    function burn(uint256 _shares) external override lock {
    //     uint256 usdBalanceBefore = TransferHelper.safeGetBalance(
    //         i_usdAddress
    //     );
    //     _burn(_shares);

    //     s_totalShares -= _shares;
    //     s_userShares[msg.sender] -= _shares;

    //     TransferHelper.safeTransfer(
    //         i_usdAddress,
    //         msg.sender,
    //         TransferHelper.safeGetBalance(i_usdAddress) - usdBalanceBefore
    //     );
    }

    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        // uint256 _currentLTV = currentLTV();
        // (
        //     uint256 token0Pool,
        //     uint256 token1Pool
        // ) = calculateCurrentPoolReserves();
        // uint256 token0Borrowed = getVToken0Balance();
        // uint256 token1Borrowed = getVToken1Balance();
        // bool tooMuchExposureTakenToken0;
        // bool tooMuchExposureTakenToken1;
        // if (token1Pool == 0 || token0Pool == 0) {
        //     tooMuchExposureTakenToken0 = true;
        //     tooMuchExposureTakenToken1 = true;
        // } else {
        //     tooMuchExposureTakenToken0 = (token0Borrowed > token0Pool)
        //         ? (((token0Borrowed - token0Pool) * PRECISION) / token0Pool >
        //             s_hedgeDev)
        //         : (
        //             (((token0Pool - token0Borrowed) * PRECISION) / token0Pool >
        //                 s_hedgeDev)
        //         );
        //     tooMuchExposureTakenToken1 = (token1Borrowed > token1Pool)
        //         ? (((token1Borrowed - token1Pool) * PRECISION) / token1Pool >
        //             s_hedgeDev)
        //         : (
        //             (((token1Pool - token1Borrowed) * PRECISION) / token1Pool >
        //                 s_hedgeDev)
        //         );
        // }
        // upkeepNeeded =
        //     (_currentLTV >= s_maxLTV ||
        //         _currentLTV <= s_minLTV ||
        //         tooMuchExposureTakenToken0 ||
        //         tooMuchExposureTakenToken1) &&
        //     (s_totalShares != 0);
        // return (upkeepNeeded, "0x0");
        return (false, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        // (bool upkeepNeeded, ) = checkUpkeep("");
        // if (!upkeepNeeded) {
        //     revert ChamberV1__UpkeepNotNeeded(currentLTV(), s_totalShares);
        // }
        // rebalance();
    }

    // =================================
    // Main funcitons helpers
    // =================================

    function _mint(uint256 usdAmount) private {
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
        (uint256 amountUsd, uint256 amountToken) = calculatePoolReserves(uint128(1e18));

        if (amountUsd == 0 || amountToken == 0) {
            revert ChamberV1__TicksOut();
        }

        uint256 usdOraclePrice = getUsdOraclePrice();
        uint256 tokenOraclePrice = getTokenOraclePrice();

        uint256 UsdToSupply =  
            (usdAmount / (amountUsd / amountToken) * tokenOraclePrice * 1e12) /
            ((usdOraclePrice * usedLTV) + (usdOraclePrice / (amountUsd / amountToken)  * 1e12));

        console.log("UsdToSupply", UsdToSupply);

        i_aaveV3Pool.supply(
            i_usdAddress,
            UsdToSupply,
            address(this),
            0
        );

        uint256 tokenToBorrow = UsdToSupply * usedLTV;

        console.log("tokenToBorrow", tokenToBorrow);

        if (tokenToBorrow > 0) {
            i_aaveV3Pool.borrow(
                i_tokenAddress,
                tokenToBorrow,
                2,
                0,
                address(this)
            );
        }

        {
            uint256 tokenRecieved = TransferHelper.safeGetBalance(
                i_tokenAddress
            ) - s_cetraFeeToken;

            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                getSqrtRatioX96(),
                MathHelper.getSqrtRatioAtTick(s_lowerTick),
                MathHelper.getSqrtRatioAtTick(s_upperTick),
                (usdAmount - UsdToSupply),
                tokenRecieved
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

    // function _burn(uint256 _shares) private {
    //     (
    //         uint256 burnToken0,
    //         uint256 burnToken1,
    //         uint256 feeToken0,
    //         uint256 feeToken1
    //     ) = _withdraw(uint128((getLiquidity() * _shares) / s_totalShares));
    //     _applyFees(feeToken0, feeToken1);

    //     uint256 amountToken0 = burnToken0 +
    //         ((TransferHelper.safeGetBalance(i_token0Address) -
    //             burnToken0 -
    //             s_cetraFeeToken0) * _shares) /
    //         s_totalShares;
    //     uint256 amountToken1 = burnToken1 +
    //         ((TransferHelper.safeGetBalance(i_token1Address) -
    //             burnToken1 -
    //             s_cetraFeeToken1) * _shares) /
    //         s_totalShares;

    //     {
    //         (
    //             uint256 token0Remainder,
    //             uint256 token1Remainder
    //         ) = _repayAndWithdraw(_shares, amountToken0, amountToken1);
    //         if (token0Remainder > 0) {
    //             swapExactAssetToStable(i_token0Address, token0Remainder);
    //         }
    //         if (token1Remainder > 0) {
    //             swapExactAssetToStable(i_token1Address, token1Remainder);
    //         }
    //     }
    // }

    // function rebalance() private {
    //     s_liquidityTokenId = false;
    //     _burn(s_totalShares);
    //     _mint(TransferHelper.safeGetBalance(i_usdAddress));
    // }

    // =================================
    // Private funcitons
    // =================================

    // function _repayAndWithdraw(
    //     uint256 _shares,
    //     uint256 token0OwnedByUser,
    //     uint256 token1OwnedByUser
    // ) private returns (uint256, uint256) {
    //     uint256 token1DebtToCover = (getVToken1Balance() * _shares) /
    //         s_totalShares;
    //     uint256 token0DebtToCover = (getVToken0Balance() * _shares) /
    //         s_totalShares;
    //     uint256 token1BalanceBefore = TransferHelper.safeGetBalance(
    //         i_token1Address
    //     );
    //     uint256 token0BalanceBefore = TransferHelper.safeGetBalance(
    //         i_token0Address
    //     );
    //     uint256 token1Remainder;
    //     uint256 token0Remainder;

    //     uint256 token0Swapped = 0;
    //     uint256 usdSwapped = 0;

    //     uint256 _currentLTV = currentLTV();
    //     if (token1OwnedByUser < token1DebtToCover) {
    //         token0Swapped += swapAssetToExactAsset(
    //             i_token0Address,
    //             i_token1Address,
    //             token1DebtToCover - token1OwnedByUser
    //         );
    //         if (
    //             token1OwnedByUser +
    //                 TransferHelper.safeGetBalance(i_token1Address) -
    //                 token1BalanceBefore <
    //             token1DebtToCover
    //         ) {
    //             revert ChamberV1__SwappedToken0ForToken1StillCantRepay();
    //         }
    //     }
    //     i_aaveV3Pool.repay(
    //         i_token1Address,
    //         token1DebtToCover,
    //         2,
    //         address(this)
    //     );
    //     if (
    //         TransferHelper.safeGetBalance(i_token1Address) >=
    //         token1BalanceBefore - token1OwnedByUser
    //     ) {
    //         token1Remainder =
    //             TransferHelper.safeGetBalance(i_token1Address) +
    //             token1OwnedByUser -
    //             token1BalanceBefore;
    //     } else {
    //         revert ChamberV1__UserRepaidMoreToken1ThanOwned();
    //     }

    //     i_aaveV3Pool.withdraw(
    //         i_usdAddress,
    //         (((1e6 * token1DebtToCover * getToken1OraclePrice()) /
    //             getUsdOraclePrice()) / _currentLTV),
    //         address(this)
    //     );

    //     if (token0OwnedByUser < token0DebtToCover + token0Swapped) {
    //         usdSwapped += swapStableToExactAsset(
    //             i_token0Address,
    //             token0DebtToCover + token0Swapped - token0OwnedByUser
    //         );
    //         if (
    //             (token0OwnedByUser +
    //                 TransferHelper.safeGetBalance(i_token0Address)) -
    //                 token0BalanceBefore <
    //             token0DebtToCover
    //         ) {
    //             revert ChamberV1__SwappedUsdForToken0StillCantRepay();
    //         }
    //     }

    //     i_aaveV3Pool.repay(
    //         i_token0Address,
    //         token0DebtToCover,
    //         2,
    //         address(this)
    //     );

    //     if (
    //         TransferHelper.safeGetBalance(i_token0Address) >=
    //         token0BalanceBefore - token0OwnedByUser
    //     ) {
    //         token0Remainder =
    //             TransferHelper.safeGetBalance(i_token0Address) +
    //             token0OwnedByUser -
    //             token0BalanceBefore;
    //     } else {
    //         revert ChamberV1__UserRepaidMoreToken0ThanOwned();
    //     }

    //     i_aaveV3Pool.withdraw(
    //         i_usdAddress,
    //         (((1e6 * token0DebtToCover * getToken0OraclePrice()) /
    //             getUsdOraclePrice()) / _currentLTV),
    //         address(this)
    //     );

    //     return (token0Remainder, token1Remainder);
    // }

    // function swapExactAssetToStable(
    //     address assetIn,
    //     uint256 amountIn
    // ) private returns (uint256) {
    //     uint256 amountOut = i_uniswapSwapRouter.exactInput(
    //         ISwapRouter.ExactInputParams({
    //             path: abi.encodePacked(assetIn, uint24(500), i_usdAddress),
    //             recipient: address(this),
    //             deadline: block.timestamp,
    //             amountIn: amountIn,
    //             amountOutMinimum: 0
    //         })
    //     );
    //     return (amountOut);
    // }

    // function swapStableToExactAsset(
    //     address assetOut,
    //     uint256 amountOut
    // ) private returns (uint256) {
    //     uint256 amountIn = i_uniswapSwapRouter.exactOutput(
    //         ISwapRouter.ExactOutputParams({
    //             path: abi.encodePacked(assetOut, uint24(500), i_usdAddress),
    //             recipient: address(this),
    //             deadline: block.timestamp,
    //             amountOut: amountOut,
    //             amountInMaximum: 1e50
    //         })
    //     );
    //     return (amountIn);
    // }

    // function swapAssetToExactAsset(
    //     address assetIn,
    //     address assetOut,
    //     uint256 amountOut
    // ) private returns (uint256) {
    //     uint256 amountIn = i_uniswapSwapRouter.exactOutput(
    //         ISwapRouter.ExactOutputParams({
    //             path: abi.encodePacked(
    //                 assetOut,
    //                 uint24(500),
    //                 i_usdAddress,
    //                 uint24(500),
    //                 assetIn
    //             ),
    //             recipient: address(this),
    //             deadline: block.timestamp,
    //             amountOut: amountOut,
    //             amountInMaximum: type(uint256).max
    //         })
    //     );

    //     return (amountIn);
    // }

    // function _withdraw(
    //     uint128 liquidityToBurn
    // ) private returns (uint256, uint256, uint256, uint256) {
    //     uint256 preBalanceToken1 = TransferHelper.safeGetBalance(
    //         i_token1Address
    //     );
    //     uint256 preBalanceToken0 = TransferHelper.safeGetBalance(
    //         i_token0Address
    //     );
    //     (uint256 burnToken0, uint256 burnToken1) = i_uniswapPool.burn(
    //         s_lowerTick,
    //         s_upperTick,
    //         liquidityToBurn
    //     );
    //     i_uniswapPool.collect(
    //         address(this),
    //         s_lowerTick,
    //         s_upperTick,
    //         type(uint128).max,
    //         type(uint128).max
    //     );
    //     uint256 feeToken1 = TransferHelper.safeGetBalance(i_token1Address) -
    //         preBalanceToken1 -
    //         burnToken1;
    //     uint256 feeToken0 = TransferHelper.safeGetBalance(i_token0Address) -
    //         preBalanceToken0 -
    //         burnToken0;
    //     return (burnToken0, burnToken1, feeToken0, feeToken1);
    // }

    // function _applyFees(uint256 _feeToken0, uint256 _feeToken1) private {
    //     s_cetraFeeToken0 += (_feeToken0 * CETRA_FEE) / PRECISION;
    //     s_cetraFeeToken1 += (_feeToken1 * CETRA_FEE) / PRECISION;
    // }

    // =================================
    // View funcitons
    // =================================

    function getAdminBalance()
        external
        view
        override
        returns (uint256, uint256)
    {
        return (s_cetraFeeUsd, s_cetraFeeToken);
    }

    function currentUSDBalance() public view override returns (uint256) {
        (
            uint256 usdPoolBalance,
            uint256 tokenPoolBalance
        ) = calculateCurrentPoolReserves();
        (
            uint256 usdFeePending,
            uint256 tokenFeePending
        ) = calculateCurrentFees();
        uint256 pureUSDAmount = getAUSDTokenBalance() +
            TransferHelper.safeGetBalance(i_usdAddress);
        uint256 poolTokensValue = ((usdPoolBalance +
            usdFeePending -
            s_cetraFeeUsd) *
            getUsdOraclePrice() +
            (tokenPoolBalance +
                tokenFeePending +
                TransferHelper.safeGetBalance(i_tokenAddress) -
                s_cetraFeeToken) *
            getTokenOraclePrice()) /
            getUsdOraclePrice() /
            1e12;
        uint256 debtTokensValue = (getVTokenBalance() *
            getTokenOraclePrice()) /
            getUsdOraclePrice() /
            1e12;
        return pureUSDAmount + poolTokensValue - debtTokensValue;
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

    function getUsdOraclePrice() private view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_usdAddress) * 1e10);
    }

    function getTokenOraclePrice() private view returns (uint256) {
        return (i_aaveOracle.getAssetPrice(i_tokenAddress) * 1e10);
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

    function getAUSDTokenBalance() private view returns (uint256) {
        return i_aaveAUSDToken.balanceOf(address(this));
    }

    function getVTokenBalance() private view returns (uint256) {
        return
            (i_aaveVToken.scaledBalanceOf(address(this)) *
                i_aaveV3Pool.getReserveNormalizedVariableDebt(
                    i_tokenAddress
                )) / 1e27;
    }

    // =================================
    // Getters
    // =================================

    function get_i_aaveVToken() external view override returns (address) {
        return address(i_aaveVToken);
    }

    function get_i_aaveAUSDToken() external view override returns (address) {
        return address(i_aaveAUSDToken);
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
                i_usdAddress,
                msg.sender,
                amount0Owed
            );
        if (amount1Owed > 0)
            TransferHelper.safeTransfer(
                i_tokenAddress,
                msg.sender,
                amount1Owed
            );
    }

    receive() external payable {}

    // =================================
    // Admin functions
    // =================================

    function _redeemFees() external override onlyOwner {
    //     TransferHelper.safeTransfer(i_token1Address, owner(), s_cetraFeeToken1);
    //     TransferHelper.safeTransfer(i_token0Address, owner(), s_cetraFeeToken0);
    //     s_cetraFeeToken1 = 0;
    //     s_cetraFeeToken0 = 0;
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
