// SPDX-License-Identifier: BSD-3-Clause
abstract contract IRouter {
    function swapExactTokensForTokensSimple(
        uint amountIn,
        uint amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint deadline
    ) external virtual returns (uint[] memory amounts);
}
