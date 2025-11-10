// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITradeValidator} from "../interfaces/ITradeValidator.sol";

contract CooldownValidator is ITradeValidator {
    function validate(
        address,
        address,
        address,
        uint256,
        uint256,
        TradeContext calldata ctx
    ) external pure returns (bool ok, bytes32 reasonCode) {
        if (ctx.cooldownRemaining > 0) {
            return (false, keccak256("COOLDOWN_NOT_ELAPSED"));
        }
        return (true, bytes32(0));
    }
}
