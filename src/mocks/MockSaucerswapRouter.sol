// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title MockSaucerswapRouter
 * @notice Mock Saucerswap router for testing with configurable exchange rates
 */
contract MockSaucerswapRouter {
    using SafeERC20 for IERC20;

    // Exchange rate: 1 tokenIn = exchangeRate tokenOut (scaled by 1e18)
    mapping(address => mapping(address => uint256)) public exchangeRates;

    event ExchangeRateSet(address tokenIn, address tokenOut, uint256 rate);

    /**
     * @notice Set exchange rate between two tokens
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param rate Exchange rate (scaled by 1e18)
     */
    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external {
        exchangeRates[tokenIn][tokenOut] = rate;
        emit ExchangeRateSet(tokenIn, tokenOut, rate);
    }

    /**
     * @notice Swap exact tokens for tokens
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Router: Expired");
        require(path.length >= 2, "Router: Invalid path");

        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        uint256 rate = exchangeRates[tokenIn][tokenOut];
        require(rate > 0, "Router: No exchange rate set");

        uint8 outDecimals = IERC20Metadata(tokenOut).decimals();

        // rate is scaled by 1e18, so: amountOut = amountIn * rate / 1e18
        // Then adjust for output token decimals
        uint256 amountOut = (amountIn * rate * (10 ** uint256(outDecimals))) / 1e18;

        require(amountOut >= amountOutMin, "Router: Insufficient output");

        // Transfer tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        return amounts;
    }

    /**
     * @notice Get expected output amounts for a given input amount
     * @param amountIn Amount of input token
     * @param path Array of token addresses representing the swap path
     * @return amounts Array of amounts for each step in the path
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts) {
        require(path.length >= 2, "Router: Invalid path");

        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        uint256 rate = exchangeRates[tokenIn][tokenOut];
        require(rate > 0, "Router: No exchange rate set");

        uint8 outDecimals = IERC20Metadata(tokenOut).decimals();

        // rate is scaled by 1e18, so: amountOut = amountIn * rate / 1e18
        // Then adjust for output token decimals
        uint256 amountOut = (amountIn * rate * (10 ** uint256(outDecimals))) / 1e18;

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        return amounts;
    }

    /**
     * @notice Fund the router with tokens for swaps
     */
    function fundRouter(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }
}
