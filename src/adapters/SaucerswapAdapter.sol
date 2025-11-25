/* SPDX-License-Identifier: GPL-2.0-or-later */
pragma solidity ^0.8.20;

import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";
import {ISwapRouterProxyHedera} from "../interfaces/ISwapRouterProxyHedera.sol";
import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IHederaTokenService {
    function associateToken(address account, address token) external returns (int64);
}

contract SaucerswapAdapter is ISwapAdapter, Ownable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error UnsupportedKind();

    ISwapRouterProxyHedera public immutable proxy;

    event AdapterSwap(address indexed caller, SwapKind kind, uint256 amountIn, uint256 amountOut);

    address private constant HTS = address(0x167);

    constructor(address _proxy) Ownable(msg.sender) {
        if (_proxy == address(0)) revert ZeroAddress();
        proxy = ISwapRouterProxyHedera(_proxy);
    }

    function swap(SwapRequest calldata req)
        external
        payable
        override
        returns (uint256 amountInUsed, uint256 amountOutReceived)
    {
        if (req.kind == SwapKind.ExactHBARForTokens) {
            uint256 outAmt = proxy.swapExactHBARForTokens{value: msg.value}(
                req.path, req.recipient, req.deadline, req.amountOutMinimum
            );
            amountInUsed = msg.value;
            amountOutReceived = outAmt;
            _sweepHBAR(req.recipient);
        } else if (req.kind == SwapKind.HBARForExactTokens) {
            uint256 inAmt = proxy.swapHBARForExactTokens{value: msg.value}(
                req.path, req.recipient, req.deadline, req.amountOut, req.amountInMaximum
            );
            amountInUsed = inAmt;
            amountOutReceived = req.amountOut;
            _sweepHBAR(req.recipient);
        } else if (req.kind == SwapKind.ExactTokensForTokens) {
            IERC20 t = IERC20(req.tokenIn);
            t.safeTransferFrom(msg.sender, address(this), req.amountIn);
            t.forceApprove(address(proxy), 0);
            t.forceApprove(address(proxy), req.amountIn);

            uint256 outAmt2 = proxy.swapExactTokensForTokens(
                req.tokenIn, req.amountIn, req.path, req.recipient, req.deadline, req.amountOutMinimum
            );

            t.forceApprove(address(proxy), 0);

            amountInUsed = req.amountIn;
            amountOutReceived = outAmt2;
        } else if (req.kind == SwapKind.TokensForExactTokens) {
            IERC20 t2 = IERC20(req.tokenIn);
            t2.safeTransferFrom(msg.sender, address(this), req.amountInMaximum);
            t2.forceApprove(address(proxy), 0);
            t2.forceApprove(address(proxy), req.amountInMaximum);

            uint256 inAmt2 = proxy.swapTokensForExactTokens(
                req.tokenIn, req.amountInMaximum, req.path, req.recipient, req.deadline, req.amountOut
            );

            if (req.amountInMaximum > inAmt2) {
                t2.safeTransfer(msg.sender, req.amountInMaximum - inAmt2);
            }
            t2.forceApprove(address(proxy), 0);

            amountInUsed = inAmt2;
            amountOutReceived = req.amountOut;
        } else if (req.kind == SwapKind.ExactTokensForHBAR) {
            IERC20 t3 = IERC20(req.tokenIn);
            t3.safeTransferFrom(msg.sender, address(this), req.amountIn);
            t3.forceApprove(address(proxy), 0);
            t3.forceApprove(address(proxy), req.amountIn);

            uint256 outHBAR = proxy.swapExactTokensForHBAR(
                req.tokenIn, req.amountIn, req.path, req.recipient, req.deadline, req.amountOutMinimum
            );

            t3.forceApprove(address(proxy), 0);

            amountInUsed = req.amountIn;
            amountOutReceived = outHBAR;
        } else if (req.kind == SwapKind.TokensForExactHBAR) {
            IERC20 t4 = IERC20(req.tokenIn);
            t4.safeTransferFrom(msg.sender, address(this), req.amountInMaximum);
            t4.forceApprove(address(proxy), 0);
            t4.forceApprove(address(proxy), req.amountInMaximum);

            uint256 inAmt3 = proxy.swapTokensForExactHBAR(
                req.tokenIn, req.amountInMaximum, req.path, req.recipient, req.deadline, req.amountOut
            );

            if (req.amountInMaximum > inAmt3) {
                t4.safeTransfer(msg.sender, req.amountInMaximum - inAmt3);
            }
            t4.forceApprove(address(proxy), 0);

            amountInUsed = inAmt3;
            amountOutReceived = req.amountOut;
        } else {
            revert UnsupportedKind();
        }

        emit AdapterSwap(msg.sender, req.kind, amountInUsed, amountOutReceived);
    }

    function _sweepHBAR(address recipient) private {
        uint256 bal = address(this).balance;
        if (bal == 0 || recipient == address(0)) return;
        (bool ok,) = payable(recipient).call{value: bal}("");
        require(ok, "Adapter: sweep HBAR failed");
    }

    // --------------------
    // Hedera: association
    // --------------------
    event AdapterAssociated(address indexed token);
    event AdapterBatchAssociated(uint256 count);

    function associateAdapterToToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        int64 rc = IHederaTokenService(HTS).associateToken(address(this), token);
        require(rc == 22 || rc == 0, "HTS associate failed"); // 22 = ALREADY_ASSOCIATED
        emit AdapterAssociated(token);
    }

    function batchAssociateAdapterToTokens(address[] calldata tokens) external onlyOwner {
        uint256 n = tokens.length;
        for (uint256 i = 0; i < n; i++) {
            address token = tokens[i];
            if (token == address(0)) revert ZeroAddress();
            int64 rc = IHederaTokenService(HTS).associateToken(address(this), token);
            require(rc == 22 || rc == 0, "HTS associate failed");
            emit AdapterAssociated(token);
        }
        emit AdapterBatchAssociated(n);
    }

    receive() external payable {}
}
