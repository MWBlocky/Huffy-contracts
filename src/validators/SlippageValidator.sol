// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITradeValidator} from "../interfaces/ITradeValidator.sol";

contract SlippageValidator is ITradeValidator {
    function validate(address, address, address, uint256, uint256, TradeContext calldata ctx)
        external
        pure
        returns (bool ok, bytes32 reasonCode)
    {
        if (ctx.impliedSlippage > ctx.maxSlippageBps) {
            return (false, keccak256("EXCEEDS_MAX_SLIPPAGE"));
        }
        return (true, bytes32(0));
    }
}

