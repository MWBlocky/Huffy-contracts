// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITradeValidator} from "../interfaces/ITradeValidator.sol";

contract PairWhitelistValidator is ITradeValidator {
    function validate(address, address, address, uint256, uint256, TradeContext calldata ctx)
        external
        pure
        returns (bool ok, bytes32 reasonCode)
    {
        if (!ctx.pairWhitelisted) {
            return (false, keccak256("PAIR_NOT_WHITELISTED"));
        }
        return (true, bytes32(0));
    }
}

