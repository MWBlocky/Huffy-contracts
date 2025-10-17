// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @notice Saucerswap Router interface
 * https://hashscan.io/mainnet/contract/0.0.3045981/abi
 * 12. function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] path, address to, uint256 deadline) returns (uint256[] amounts) NONPAYABLE 0x38ed1739
 */
interface ISaucerswapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Get expected output amounts for a given input amount
     * @param amountIn Amount of input token
     * @param path Array of token addresses representing the swap path
     * @return amounts Array of amounts for each step in the path
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}
