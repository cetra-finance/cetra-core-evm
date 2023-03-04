// SPDX-License-Identifier: BSD-3-Clause
abstract contract IComptroller {
    function getAccountLiquidity(
        address account
    ) public view virtual returns (uint, uint, uint);

    function enterMarkets(
        address[] memory cTokens
    ) public virtual returns (uint[] memory);

    function claimComp(address holder) public virtual;
}
