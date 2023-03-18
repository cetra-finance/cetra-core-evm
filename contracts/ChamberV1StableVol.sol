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

/*Errors */
error ChamberV1__ReenterancyGuard();
error ChamberV1__AaveDepositError();
error ChamberV1__UserRepaidMoreTokenThanOwned();
error ChamberV1__SwappedUsdForTokenStillCantRepay();
error ChamberV1__CallerIsNotUniPool();
error ChamberV1__sharesWorthMoreThenDep();
error ChamberV1__TicksOut();
error ChamberV1__UpkeepNotNeeded(uint256 _currentLTV, uint256 _totalShares);

// For Wmatic/Weth
contract ChamberV1StableVol is
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

    uint256 private constant USD_RATE = 1e6;
    uint256 private constant TOKEN_RATE = 1e18;

    bool private constant ZERO_IS_VOL = false;

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
        uint256 usdBalanceBefore = TransferHelper.safeGetBalance(i_usdAddress);
        uint256 feeBefore = s_cetraFeeUsd;
        _burn(_shares);
        s_totalShares -= _shares;
        s_userShares[msg.sender] -= _shares;
        TransferHelper.safeTransfer(
            i_usdAddress,
            msg.sender,
            TransferHelper.safeGetBalance(i_usdAddress) -
                usdBalanceBefore -
                s_cetraFeeUsd +
                feeBefore
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
        {
            (, uint256 tokenPool) = calculateCurrentPoolReserves();
            if (tokenPool == 0) {
                return (true, "0x0");
            }
        }

        uint256 _currentLTV = currentLTV();
        uint256 _currentHedgeDev = currentHedgeDev();
        upkeepNeeded =
            (_currentLTV >= s_maxLTV ||
                _currentLTV <= s_minLTV ||
                _currentHedgeDev > s_hedgeDev) &&
            (s_totalShares != 0);
        return (upkeepNeeded, "0x0");
    }

    function currentHedgeDev() private view returns (uint256) {
        (, uint256 tokenPool) = calculateCurrentPoolReserves();
        uint256 hedgeDev;
        if (tokenPool != 0) {
            uint256 tokenBorrowed = getVTokenBalance();
            hedgeDev = (tokenBorrowed > tokenPool)
                ? (((tokenBorrowed - tokenPool) * PRECISION) / tokenPool)
                : ((((tokenPool - tokenBorrowed) * PRECISION) / tokenPool));
        } else {
            hedgeDev = 0;
        }
        return hedgeDev;
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
        uint256 usedLTV;

        int24 currentTick = getTick();
        uint256 usdOraclePrice = getUsdOraclePrice();
        uint256 tokenOraclePrice = getTokenOraclePrice();
        uint256 amountUsd;
        uint256 amountToken;

        if (!s_liquidityTokenId) {
            s_lowerTick = ((currentTick - s_ticksRange) / 60) * 60;
            s_upperTick = ((currentTick + s_ticksRange) / 60) * 60;
            usedLTV = s_targetLTV;
        } else {
            usedLTV = currentLTV();
        }
        if (usedLTV < (10 * PRECISION) / 100) {
            usedLTV = s_targetLTV;
        }
        (amountUsd, amountToken) = calculatePoolReserves(uint128(1e18));
        if (amountUsd == 0 || amountToken == 0) {
            revert ChamberV1__TicksOut();
        }

        uint256 UsdToSupply = ((tokenOraclePrice * usdAmount * amountToken) /
            amountUsd) /
            PRECISION /
            ((((usdOraclePrice * usedLTV) * TOKEN_RATE) / USD_RATE) /
                PRECISION /
                PRECISION +
                ((tokenOraclePrice * amountToken) / amountUsd / PRECISION));

        i_aaveV3Pool.supply(i_usdAddress, UsdToSupply, address(this), 0);

        uint256 tokenToBorrow = ((((UsdToSupply * usedLTV * usdOraclePrice) /
            tokenOraclePrice) / PRECISION) * TOKEN_RATE) / USD_RATE;
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

            uint256 tokenToDeposit = tokenRecieved;

            if (s_liquidityTokenId) {
                (amountUsd, amountToken) = calculatePoolReserves(
                    getLiquidity()
                );
                uint256 poolSkew = getVTokenBalance() > tokenRecieved
                    ? (PRECISION * amountToken) /
                        (getVTokenBalance() - tokenRecieved)
                    : PRECISION;
                tokenToDeposit = (tokenRecieved * poolSkew) / PRECISION;
                if (poolSkew > PRECISION) {
                    if (tokenToDeposit - tokenRecieved > 1e6) {
                        swapStableToExactAsset(
                            i_tokenAddress,
                            tokenToDeposit - tokenRecieved
                        );
                    }
                } else {
                    if (tokenRecieved - tokenToDeposit > 1e6) {
                        swapExactAssetToStable(
                            i_tokenAddress,
                            tokenRecieved - tokenToDeposit
                        );
                    }
                }
            }

            (amountUsd, amountToken) = calculatePoolReserves(uint128(1e18));

            uint256 usdRemained = TransferHelper.safeGetBalance(i_usdAddress) -
                s_cetraFeeUsd;
            if ((tokenToDeposit * amountUsd) / amountToken > usdRemained) {
                i_aaveV3Pool.withdraw(
                    i_usdAddress,
                    (tokenToDeposit * amountUsd) / amountToken - usdRemained,
                    address(this)
                );
            } else {
                i_aaveV3Pool.supply(
                    i_usdAddress,
                    usdRemained - (tokenToDeposit * amountUsd) / amountToken,
                    address(this),
                    0
                );
            }

            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                getSqrtRatioX96(),
                MathHelper.getSqrtRatioAtTick(s_lowerTick),
                MathHelper.getSqrtRatioAtTick(s_upperTick),
                (tokenToDeposit * amountUsd) / amountToken,
                tokenToDeposit
            );

            i_uniswapPool.mint(
                address(this),
                s_lowerTick,
                s_upperTick,
                liquidityMinted,
                ""
            );
        }
        s_liquidityTokenId = true;
    }

    function _burn(uint256 _shares) private {
        (, uint256 burnToken, uint256 feeUsd, uint256 feeToken) = _withdraw(
            uint128((getLiquidity() * _shares) / s_totalShares)
        );
        _applyFees(feeUsd, feeToken);

        uint256 amountToken = burnToken +
            ((TransferHelper.safeGetBalance(i_tokenAddress) -
                burnToken -
                s_cetraFeeToken) * _shares) /
            s_totalShares;

        {
            uint256 tokenRemainder = _repayAndWithdraw(_shares, amountToken);
            if (tokenRemainder > 0) {
                swapExactAssetToStable(i_tokenAddress, tokenRemainder);
            }
        }
    }

    function rebalance() private {
        s_liquidityTokenId = false;
        _burn(s_totalShares);
        _mint(TransferHelper.safeGetBalance(i_usdAddress) - s_cetraFeeUsd);
    }

    // =================================
    // Private funcitons
    // =================================

    function _repayAndWithdraw(
        uint256 _shares,
        uint256 tokenOwnedByUser
    ) private returns (uint256) {
        uint256 tokenDebtToCover = (getVTokenBalance() * _shares) /
            s_totalShares;

        uint256 tokenBalanceBefore = TransferHelper.safeGetBalance(
            i_tokenAddress
        );

        uint256 tokenRemainder;

        uint256 _currentLTV = currentLTV();
        if (tokenOwnedByUser < tokenDebtToCover) {
            swapStableToExactAsset(
                i_tokenAddress,
                tokenDebtToCover - tokenOwnedByUser
            );
            if (
                tokenOwnedByUser +
                    TransferHelper.safeGetBalance(i_tokenAddress) -
                    tokenBalanceBefore <
                tokenDebtToCover
            ) {
                revert ChamberV1__SwappedUsdForTokenStillCantRepay();
            }
        }
        i_aaveV3Pool.repay(i_tokenAddress, tokenDebtToCover, 2, address(this));
        if (
            TransferHelper.safeGetBalance(i_tokenAddress) >=
            tokenBalanceBefore - tokenOwnedByUser
        ) {
            tokenRemainder =
                TransferHelper.safeGetBalance(i_tokenAddress) +
                tokenOwnedByUser -
                tokenBalanceBefore;
        } else {
            revert ChamberV1__UserRepaidMoreTokenThanOwned();
        }

        i_aaveV3Pool.withdraw(
            i_usdAddress,
            (((USD_RATE * tokenDebtToCover * getTokenOraclePrice()) /
                getUsdOraclePrice()) / _currentLTV),
            address(this)
        );
        return (tokenRemainder);
    }

    function swapExactAssetToStable(
        address assetIn,
        uint256 amountIn
    ) private returns (uint256) {
        uint256 amountOut = i_uniswapSwapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(assetIn, uint24(500), i_usdAddress),
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
                path: abi.encodePacked(assetOut, uint24(500), i_usdAddress),
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
                    uint24(500),
                    i_usdAddress,
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
    ) private returns (uint256, uint256, uint256, uint256) {
        uint256 preBalanceUsd = TransferHelper.safeGetBalance(i_usdAddress);
        uint256 preBalanceToken = TransferHelper.safeGetBalance(i_tokenAddress);
        (uint256 burnUsd, uint256 burnToken) = i_uniswapPool.burn(
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
        uint256 feeUsd = TransferHelper.safeGetBalance(i_usdAddress) -
            preBalanceUsd -
            burnUsd;
        uint256 feeToken = TransferHelper.safeGetBalance(i_tokenAddress) -
            preBalanceToken -
            burnToken;
        return (burnUsd, burnToken, feeUsd, feeToken);
    }

    function _applyFees(uint256 _feeUsd, uint256 _feeToken) private {
        s_cetraFeeUsd += (_feeUsd * CETRA_FEE) / PRECISION;
        s_cetraFeeToken += (_feeToken * CETRA_FEE) / PRECISION;
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
        uint256 poolTokensValue = (usdPoolBalance + usdFeePending) +
            (((tokenPoolBalance +
                tokenFeePending +
                TransferHelper.safeGetBalance(i_tokenAddress)) *
                getTokenOraclePrice()) /
                getUsdOraclePrice() /
                TOKEN_RATE) *
            USD_RATE;
        uint256 debtTokensValue = ((getVTokenBalance() *
            getTokenOraclePrice()) /
            getUsdOraclePrice() /
            TOKEN_RATE) * USD_RATE;
        uint256 positiveBalanceWithFees = pureUSDAmount + poolTokensValue;
        uint256 feesValue = s_cetraFeeUsd +
            ((s_cetraFeeToken * getTokenOraclePrice()) /
                getUsdOraclePrice() /
                TOKEN_RATE) *
            USD_RATE;

        return
            (positiveBalanceWithFees > debtTokensValue)
                ? (
                    (positiveBalanceWithFees - debtTokensValue > feesValue)
                        ? (positiveBalanceWithFees -
                            debtTokensValue -
                            feesValue)
                        : (0)
                )
                : (0);
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
                i_aaveV3Pool.getReserveNormalizedVariableDebt(i_tokenAddress)) /
            1e27;
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
            TransferHelper.safeTransfer(i_usdAddress, msg.sender, amount0Owed);
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
        TransferHelper.safeTransfer(i_usdAddress, owner(), s_cetraFeeUsd);
        TransferHelper.safeTransfer(i_tokenAddress, owner(), s_cetraFeeToken);
        s_cetraFeeUsd = 0;
        s_cetraFeeToken = 0;
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