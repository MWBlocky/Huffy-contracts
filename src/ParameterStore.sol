// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

/**
 * @title ParameterStore
 * @notice DAO-controlled store for risk parameters used by Relay and other modules
 * @dev Centralizes configuration to a single contract governed by DAO_ROLE
 */
contract ParameterStore is AccessControl {
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");

    // Risk parameters (DAO-controlled)
    uint256 public maxTradeBps; // Max trade size as % of Treasury balance (basis points, e.g., 1000 = 10%)
    uint256 public maxSlippageBps; // Max allowed slippage (basis points)
    uint256 public tradeCooldownSec; // Minimum seconds between trades

    // Events
    event MaxTradeBpsUpdated(uint256 oldValue, uint256 newValue, uint256 timestamp);
    event MaxSlippageBpsUpdated(uint256 oldValue, uint256 newValue, uint256 timestamp);
    event TradeCooldownSecUpdated(uint256 oldValue, uint256 newValue, uint256 timestamp);

    /**
     * @notice Constructor
     * @param admin Address of admin (DAO multisig)
     * @param _maxTradeBps Initial max trade size in basis points
     * @param _maxSlippageBps Initial max slippage in basis points
     * @param _tradeCooldownSec Initial cooldown period in seconds
     */
    constructor(address admin, uint256 _maxTradeBps, uint256 _maxSlippageBps, uint256 _tradeCooldownSec) {
        require(admin != address(0), "ParameterStore: invalid admin");
        require(_maxTradeBps <= 10000, "ParameterStore: invalid maxTradeBps");
        require(_maxSlippageBps <= 10000, "ParameterStore: invalid maxSlippageBps");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DAO_ROLE, admin);

        maxTradeBps = _maxTradeBps;
        maxSlippageBps = _maxSlippageBps;
        tradeCooldownSec = _tradeCooldownSec;
    }

    /**
     * @notice Update maxTradeBps parameter
     */
    function setMaxTradeBps(uint256 newMaxTradeBps) external onlyRole(DAO_ROLE) {
        require(newMaxTradeBps <= 10000, "ParameterStore: invalid maxTradeBps");
        uint256 oldValue = maxTradeBps;
        maxTradeBps = newMaxTradeBps;
        emit MaxTradeBpsUpdated(oldValue, newMaxTradeBps, block.timestamp);
    }

    /**
     * @notice Update maxSlippageBps parameter
     */
    function setMaxSlippageBps(uint256 newMaxSlippageBps) external onlyRole(DAO_ROLE) {
        require(newMaxSlippageBps <= 10000, "ParameterStore: invalid maxSlippageBps");
        uint256 oldValue = maxSlippageBps;
        maxSlippageBps = newMaxSlippageBps;
        emit MaxSlippageBpsUpdated(oldValue, newMaxSlippageBps, block.timestamp);
    }

    /**
     * @notice Update tradeCooldownSec parameter
     */
    function setTradeCooldownSec(uint256 newTradeCooldownSec) external onlyRole(DAO_ROLE) {
        uint256 oldValue = tradeCooldownSec;
        tradeCooldownSec = newTradeCooldownSec;
        emit TradeCooldownSecUpdated(oldValue, newTradeCooldownSec, block.timestamp);
    }

    /**
     * @notice Get current risk parameters snapshot
     */
    function getRiskParameters()
        external
        view
        returns (uint256 _maxTradeBps, uint256 _maxSlippageBps, uint256 _tradeCooldownSec)
    {
        return (maxTradeBps, maxSlippageBps, tradeCooldownSec);
    }
}
