// SPDX-License-Identifier: BSD-3-Clause
abstract contract ICErc20 {
    address public underlying;

    function mint(uint mintAmount) external virtual returns (uint);

    function redeem(uint redeemTokens) external virtual returns (uint);

    function redeemUnderlying(
        uint redeemAmount
    ) external virtual returns (uint);

    function borrow(uint borrowAmount) external virtual returns (uint);

    function repayBorrow(uint repayAmount) external virtual returns (uint);

    function borrowBalanceStored(
        address account
    ) external view virtual returns (uint);

    function exchangeRateStored() external view virtual returns (uint);

    function balanceOf(address owner) external view virtual returns (uint256);
}
