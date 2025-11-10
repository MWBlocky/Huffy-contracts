// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITradeValidator} from "../interfaces/ITradeValidator.sol";

contract BasicParamsValidator is ITradeValidator {
    function validate(
        address,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        TradeContext calldata
    ) external pure returns (bool ok, bytes32 reasonCode) {
        if (tokenIn == address(0) || tokenOut == address(0) || amountIn == 0 || minAmountOut == 0) {
            return (false, keccak256("INVALID_PARAMETERS"));
        }
        return (true, bytes32(0));
    }
}


