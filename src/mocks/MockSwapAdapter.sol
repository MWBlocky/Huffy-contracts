// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";
import {MockSaucerswapRouter} from "./MockSaucerswapRouter.sol";
import {SafeERC20, IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice Simple swap adapter used in tests that wraps the MockSaucerswapRouter
 */
contract MockSwapAdapter is ISwapAdapter {
    using SafeERC20 for IERC20;

    error UnsupportedKind();

    MockSaucerswapRouter public immutable router;

    constructor(address _router) {
        router = MockSaucerswapRouter(_router);
    }

    function swap(SwapRequest calldata req)
        external
        payable
        override
        returns (uint256 amountInUsed, uint256 amountOutReceived)
    {
        if (req.kind != SwapKind.ExactTokensForTokens) {
            revert UnsupportedKind();
        }
        require(req.recipient != address(0), "Adapter: invalid recipient");

        address[] memory decodedPath = abi.decode(req.path, (address[]));
        require(decodedPath.length >= 2, "Adapter: invalid path");

        address tokenOut = decodedPath[decodedPath.length - 1];

        IERC20(req.tokenIn).safeTransferFrom(msg.sender, address(this), req.amountIn);
        IERC20(req.tokenIn).approve(address(router), 0);
        IERC20(req.tokenIn).approve(address(router), req.amountIn);

        uint256 outBefore = IERC20(tokenOut).balanceOf(req.recipient);
        router.swapExactTokensForTokens(req.amountIn, req.amountOutMinimum, decodedPath, req.recipient, req.deadline);
        uint256 outAfter = IERC20(tokenOut).balanceOf(req.recipient);

        amountInUsed = req.amountIn;
        amountOutReceived = outAfter - outBefore;
    }
}
