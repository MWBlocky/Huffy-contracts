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

        (address tokenInParsed, address tokenOut) = _decodePath(req.path);
        require(req.tokenIn == tokenInParsed, "Adapter: tokenIn mismatch");
        address[] memory decodedPath = new address[](2);
        decodedPath[0] = tokenInParsed;
        decodedPath[1] = tokenOut;

        IERC20(req.tokenIn).safeTransferFrom(msg.sender, address(this), req.amountIn);
        IERC20(req.tokenIn).approve(address(router), 0);
        IERC20(req.tokenIn).approve(address(router), req.amountIn);

        uint256 outBefore = IERC20(tokenOut).balanceOf(req.recipient);
        router.swapExactTokensForTokens(req.amountIn, req.amountOutMinimum, decodedPath, req.recipient, req.deadline);
        uint256 outAfter = IERC20(tokenOut).balanceOf(req.recipient);

        amountInUsed = req.amountIn;
        amountOutReceived = outAfter - outBefore;
    }

    function _decodePath(bytes memory path) private pure returns (address tokenIn, address tokenOut) {
        if (path.length >= 43 && (path.length - 20) % 23 == 0) {
            tokenIn = _readAddress(path, 0);
            uint256 tokenCount = 1 + (path.length - 20) / 23;
            uint256 lastOffset = 23 * (tokenCount - 1);
            tokenOut = _readAddress(path, lastOffset);
            return (tokenIn, tokenOut);
        }
        address[] memory decoded = abi.decode(path, (address[]));
        require(decoded.length >= 2, "Adapter: invalid path");
        tokenIn = decoded[0];
        tokenOut = decoded[decoded.length - 1];
    }

    function _readAddress(bytes memory data, uint256 start) private pure returns (address addr) {
        require(data.length >= start + 20, "Adapter: path read overflow");
        assembly {
            addr := shr(96, mload(add(add(data, 0x20), start)))
        }
    }
}
