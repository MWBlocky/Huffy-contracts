// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISwapAdapter
 * @notice Unified adapter interface for executing swaps through chain-specific routers
 */
interface ISwapAdapter {
    enum SwapKind {
        ExactHBARForTokens,
        HBARForExactTokens,
        ExactTokensForTokens,
        TokensForExactTokens,
        ExactTokensForHBAR,
        TokensForExactHBAR
    }

    struct SwapRequest {
        SwapKind kind;
        address tokenIn;
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint256 amountOutMinimum;
    }

    function swap(SwapRequest calldata req)
        external
        payable
        returns (uint256 amountInUsed, uint256 amountOutReceived);
}
