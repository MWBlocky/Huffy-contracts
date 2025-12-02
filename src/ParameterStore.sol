// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ParameterStore
 * @notice Timelock-governed store for risk parameters used by Relay and other modules
 * @dev Centralizes configuration to a single contract. Mutations are only allowed by the Timelock.
 */
contract ParameterStore {
    uint256 public constant MAX_BPS = 10_000;

    error NotTimelock(address caller, address timelock);
    error InvalidBps();
    error ZeroAddress();

    address public immutable TIMELOCK;

    // Risk parameters (governance-controlled)
    uint256 public maxTradeBps; // Max trade size as % of Treasury balance (basis points, e.g., 1000 = 10%)
    uint256 public maxSlippageBps; // Max allowed slippage (basis points)
    uint256 public tradeCooldownSec; // Minimum seconds between trades

    event ParamsUpdated(
        uint256 oldMaxTradeBps,
        uint256 newMaxTradeBps,
        uint256 oldMaxSlippageBps,
        uint256 newMaxSlippageBps,
        uint256 oldTradeCooldownSec,
        uint256 newTradeCooldownSec,
        uint256 timestamp
    );

    modifier onlyTimelock() {
        if (msg.sender != TIMELOCK) revert NotTimelock(msg.sender, TIMELOCK);
        _;
    }

    /**
     * @notice Constructor
     * @param _timelock Address of governance Timelock
     * @param _maxTradeBps Initial max trade size in basis points
     * @param _maxSlippageBps Initial max slippage in basis points
     * @param _tradeCooldownSec Initial cooldown period in seconds
     */

    constructor(address _timelock, uint256 _maxTradeBps, uint256 _maxSlippageBps, uint256 _tradeCooldownSec) {
        if (_timelock == address(0)) revert ZeroAddress();
        if (_maxTradeBps > MAX_BPS) revert InvalidBps();
        if (_maxSlippageBps > MAX_BPS) revert InvalidBps();

        TIMELOCK = _timelock;
        maxTradeBps = _maxTradeBps;
        maxSlippageBps = _maxSlippageBps;
        tradeCooldownSec = _tradeCooldownSec;
    }

    function setParameters(uint256 newMaxTradeBps, uint256 newMaxSlippageBps, uint256 newTradeCooldownSec)
        external
        onlyTimelock
    {
        _setParameters(newMaxTradeBps, newMaxSlippageBps, newTradeCooldownSec);
    }

    function setMaxTradeBps(uint256 newMaxTradeBps) external onlyTimelock {
        _setParameters(newMaxTradeBps, maxSlippageBps, tradeCooldownSec);
    }

    function setMaxSlippageBps(uint256 newMaxSlippageBps) external onlyTimelock {
        _setParameters(maxTradeBps, newMaxSlippageBps, tradeCooldownSec);
    }

    function setTradeCooldownSec(uint256 newTradeCooldownSec) external onlyTimelock {
        _setParameters(maxTradeBps, maxSlippageBps, newTradeCooldownSec);
    }

    function getRiskParameters()
        external
        view
        returns (uint256 _maxTradeBps, uint256 _maxSlippageBps, uint256 _tradeCooldownSec)
    {
        return (maxTradeBps, maxSlippageBps, tradeCooldownSec);
    }

    function _setParameters(uint256 newMaxTradeBps, uint256 newMaxSlippageBps, uint256 newTradeCooldownSec) internal {
        if (newMaxTradeBps > MAX_BPS) revert InvalidBps();
        if (newMaxSlippageBps > MAX_BPS) revert InvalidBps();

        uint256 oldMaxTradeBps = maxTradeBps;
        uint256 oldMaxSlippageBps = maxSlippageBps;
        uint256 oldTradeCooldownSec = tradeCooldownSec;

        maxTradeBps = newMaxTradeBps;
        maxSlippageBps = newMaxSlippageBps;
        tradeCooldownSec = newTradeCooldownSec;

        emit ParamsUpdated(
            oldMaxTradeBps,
            newMaxTradeBps,
            oldMaxSlippageBps,
            newMaxSlippageBps,
            oldTradeCooldownSec,
            newTradeCooldownSec,
            block.timestamp
        );
    }
}
