// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

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

/*Errors */
error ChamberV1__AaveDepositError();
error ChamberV1__UserRepaidMoreEthThanOwned();
error ChamberV1__UserRepaidMoreMaticThanOwned();
error ChamberV1__SwappedWethForWmaticStillCantRepay();
error ChamberV1__SwappedWmaticForWethStillCantRepay();
error ChamberV1__SwappedUsdcForWethStillCantRepay();
error ChamberV1__CallerIsNotUniPool();
error ChamberV1__sharesWorthMoreThenDep();
error ChamberV1__UpkeepNotNeeded(uint256 _currentLTV, uint256 _totalShares);

contract ChamberV1 is
    Ownable,
    IUniswapV3MintCallback,
    AutomationCompatibleInterface
{
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

    bool private unlocked;

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

    // ================================
    // Modifiers
    // =================================

    modifier lock() {
        require(unlocked, "LOK");
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
        unlocked = true;
    }

    // =================================
    // Main funcitons
    // =================================

    function mint(uint256 usdAmount) external lock {
        {
            uint256 currUsdBalance = currentUSDBalance();
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
        _mint(usdAmount);
    }

    function burn(uint256 _shares) external lock {
        uint256 usdcBalanceBefore = TransferHelper.safeGetBalance(
            i_usdcAddress,
            address(this)
        );
        _burn(_shares);

        s_totalShares -= _shares;
        s_userShares[msg.sender] -= _shares;

        TransferHelper.safeTransfer(
            i_usdcAddress,
            msg.sender,
            TransferHelper.safeGetBalance(i_usdcAddress, address(this)) -
                usdcBalanceBefore
        );
    }

    function performUpkeep(bytes calldata /* performData */) external override lock {
        (bool upkeepNeeded, ) = checkUpkeep("");
        // require(upkeepNeeded, "Upkeep not needed");
        if (!upkeepNeeded) {
            revert ChamberV1__UpkeepNotNeeded(currentLTV(), s_totalShares);
        }
        rebalance();
    }

    // =================================
    // Main funcitons helpers
    // =================================

    function _mint(uint256 usdAmount) internal {
        uint256 amount0;
        uint256 amount1;
        uint256 usedLTV;

        int24 currentTick = getTick();

        if (!s_liquidityTokenId) {
            s_lowerTick = ((currentTick - 700) / 10) * 10;
            s_upperTick = ((currentTick + 700) / 10) * 10;
            (amount0, amount1) = calculatePoolReserves(
                currentTick,
                uint128(1e18)
            );
            usedLTV = s_targetLTV;
            s_liquidityTokenId = true;
        } else {
            usedLTV = currentLTV();
            (amount0, amount1) = calculatePoolReserves(
                currentTick,
                getLiquidity()
            );
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
            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                getSqrtRatioX96(),
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

    function _burn(uint256 _shares) internal {
        (uint256 burnWMATIC, uint256 burnWETH) = _withdraw(
            uint128((getPositionLiquidity() * _shares) / s_totalShares),
            _shares
        );

        uint256 amountWmatic = burnWMATIC +
            ((TransferHelper.safeGetBalance(i_wmaticAddress, address(this)) -
                burnWMATIC) * _shares) /
            s_totalShares;
        uint256 amountWeth = burnWETH +
            ((TransferHelper.safeGetBalance(i_wethAddress, address(this)) -
                burnWETH) * _shares) /
            s_totalShares;

        {
            (
                uint256 wmaticRemainder,
                uint256 wethRemainder
            ) = _repayAndWithdraw(_shares, amountWmatic, amountWeth);
            if (wmaticRemainder > 0) {
                swapExactAssetToStable(i_wmaticAddress, wmaticRemainder);
            }
            if (wethRemainder > 0) {
                swapExactAssetToStable(i_wethAddress, wethRemainder);
            }
        }
    }

    function rebalance() private {
        _burn(s_totalShares);
        _mint(TransferHelper.safeGetBalance(i_usdcAddress, address(this)));
    }

    // =================================
    // Internal funcitons
    // =================================

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
            }
        }
        i_aaveV3Pool.repay(
            i_wmaticAddress,
            wmaticDebtToCover,
            2,
            address(this)
        );
        if (
            TransferHelper.safeGetBalance(i_wmaticAddress, address(this)) >=
            wmaticBalanceBefore - wmaticOwnedByUser
        ) {
            wmaticRemainder =
                TransferHelper.safeGetBalance(i_wmaticAddress, address(this)) +
                wmaticOwnedByUser -
                wmaticBalanceBefore;
        } else {
            revert ChamberV1__UserRepaidMoreMaticThanOwned();
        }

        i_aaveV3Pool.withdraw(
            i_usdcAddress,
            (((1e6 * wmaticDebtToCover * getWmaticOraclePrice()) /
                getUsdcOraclePrice()) / _currentLTV),
            address(this)
        );

        if (wethOwnedByUser < wethDebtToCover + wethSwapped) {
            usdcSwapped += swapStableToExactAsset(
                i_wethAddress,
                wethDebtToCover + wethSwapped - wethOwnedByUser
            );
            if (
                (wethOwnedByUser +
                    TransferHelper.safeGetBalance(
                        i_wethAddress,
                        address(this)
                    )) -
                    wethBalanceBefore <
                wethDebtToCover
            ) {
                revert ChamberV1__SwappedUsdcForWethStillCantRepay();
            }
        }
        i_aaveV3Pool.repay(i_wethAddress, wethDebtToCover, 2, address(this));

        if (
            TransferHelper.safeGetBalance(i_wethAddress, address(this)) >=
            wethBalanceBefore - wethOwnedByUser
        ) {
            wethRemainder =
                TransferHelper.safeGetBalance(i_wethAddress, address(this)) +
                wethOwnedByUser -
                wethBalanceBefore;
        } else {
            revert ChamberV1__UserRepaidMoreEthThanOwned();
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
        uint256 amountIn
    ) internal returns (uint256) {
        uint256 amountOut = i_uniswapSwapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(assetIn, uint24(500), i_usdcAddress),
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
    ) internal returns (uint256) {
        uint256 amountIn = i_uniswapSwapRouter.exactOutput(
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(assetOut, uint24(500), i_usdcAddress),
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
        uint128 liquidityToBurn,
        uint256 _shares
    ) internal returns (uint256, uint256) {
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
        // maybe should make function "collectAndReinvest" to call it before withdraws.
        // And although make it available for harvesters to reinvest for fee
        i_uniswapPool.collect(
            address(this),
            s_lowerTick,
            s_upperTick,
            type(uint128).max,
            type(uint128).max
        );

        return (burnWMATIC, burnWETH);
    }

    // =================================
    // View funcitons
    // =================================

    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        uint256 _currentLTV = currentLTV();
        bool ltvOutOfBounds = _currentLTV >= s_maxLTV ||
            _currentLTV <= s_minLTV;
        bool fundsDeposited = s_totalShares != 0;
        upkeepNeeded = (ltvOutOfBounds && fundsDeposited);
        return (upkeepNeeded, "0x0");
    }

    function currentUSDBalance() public view returns (uint256) {
        (
            uint256 wmaticPoolBalance,
            uint256 wethPoolBalance
        ) = calculateCurrentPoolReserves();
        (
            uint256 wmaticFeePending,
            uint256 wethFeePending
        ) = calculateCurrentFees();
        uint256 pureUSDCAmount = getAUSDCTokenBalance() +
            TransferHelper.safeGetBalance(i_usdcAddress, address(this));
        uint256 poolTokensValue = ((wethPoolBalance +
            wethFeePending +
            TransferHelper.safeGetBalance(i_wethAddress, address(this))) *
            getWethOraclePrice() +
            (wmaticPoolBalance +
                wmaticFeePending +
                TransferHelper.safeGetBalance(i_wmaticAddress, address(this))) *
            getWmaticOraclePrice()) /
            getUsdcOraclePrice() /
            1e12;
        uint256 debtTokensValue = (getVWETHTokenBalance() *
            getWethOraclePrice() +
            getVWMATICTokenBalance() *
            getWmaticOraclePrice()) /
            getUsdcOraclePrice() /
            1e12;
        return pureUSDCAmount + poolTokensValue - debtTokensValue;
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
        uint256 ltv = totalCollateralETH == 0
            ? 0
            : (PRECISION * totalBorrowedETH) / totalCollateralETH;
        return ltv;
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

    function getSqrtRatioX96() public view returns (uint160) {
        (uint160 sqrtRatioX96, , , , , , ) = i_uniswapPool.slot0();
        return sqrtRatioX96;
    }

    function calculateCurrentPoolReserves()
        public
        view
        returns (uint256 amount0Current, uint256 amount1Current)
    {
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
                getSqrtRatioX96(),
                MathHelper.getSqrtRatioAtTick(s_lowerTick),
                MathHelper.getSqrtRatioAtTick(s_upperTick),
                liquidity
            );

        return (amount0Current, amount1Current);
    }

    function getLiquidity() internal view returns (uint128) {
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

    function calculatePoolReserves(
        int24 _currentTick,
        uint128 liquidity
    ) internal view returns (uint256, uint256) {
        uint256 amount0;
        uint256 amount1;
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            MathHelper.getSqrtRatioAtTick(_currentTick),
            MathHelper.getSqrtRatioAtTick(s_lowerTick),
            MathHelper.getSqrtRatioAtTick(s_upperTick),
            liquidity
        );
        return (amount0, amount1);
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
                i_wmaticAddress,
                msg.sender,
                amount0Owed
            );
        if (amount1Owed > 0)
            TransferHelper.safeTransfer(i_wethAddress, msg.sender, amount1Owed);
    }

    receive() external payable {}

    // =================================
    // Admin functions
    // =================================

    function giveApprove(address _token, address _to) public onlyOwner {
        TransferHelper.safeApprove(_token, _to, type(uint256).max);
    }

    function setLTV(
        uint256 _targetLTV,
        uint256 _minLTV,
        uint256 _maxLTV
    ) public onlyOwner {
        s_targetLTV = _targetLTV;
        s_minLTV = _minLTV;
        s_maxLTV = _maxLTV;
    }
}
