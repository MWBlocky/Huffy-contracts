// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Treasury} from "../Treasury.sol";

/**
 * @title MockRelay
 * @notice Mock Relay contract for testing Treasury integration
 */
contract MockRelay {
    Treasury public treasury;

    constructor(address _treasury) {
        require(_treasury != address(0), "MockRelay: Invalid treasury");
        treasury = Treasury(_treasury);
    }

    function executeBuybackAndBurn(address tokenIn, uint256 amountIn, uint256 amountOutMin, uint256 deadline)
        external
        returns (uint256)
    {
        return treasury.executeBuybackAndBurn(tokenIn, amountIn, amountOutMin, deadline);
    }
}
