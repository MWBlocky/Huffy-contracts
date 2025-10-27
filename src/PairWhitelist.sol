// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PairWhitelist
 * @notice Registry of governance-approved trading pairs
 * @dev Timelock-controlled: only the Timelock can add/remove pairs
 */
contract PairWhitelist {
    address public immutable TIMELOCK;

    // Mapping: tokenIn => tokenOut => isWhitelisted
    mapping(address => mapping(address => bool)) private _whitelist;

    // Events
    event PairAdded(address indexed tokenIn, address indexed tokenOut);
    event PairRemoved(address indexed tokenIn, address indexed tokenOut);

    constructor(address _timelock) {
        require(_timelock != address(0), "PairWhitelist: invalid timelock");
        TIMELOCK = _timelock;
    }

    modifier onlyTimelock() {
        _onlyTimelock();
        _;
    }

    function _onlyTimelock() internal view {
        require(msg.sender == TIMELOCK, "PairWhitelist: only Timelock");
    }

    /**
     * @notice Add a trading pair to the whitelist
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     */
    function addPair(address tokenIn, address tokenOut) external onlyTimelock {
        require(tokenIn != address(0) && tokenOut != address(0), "PairWhitelist: invalid token");
        require(tokenIn != tokenOut, "PairWhitelist: same token");
        require(!_whitelist[tokenIn][tokenOut], "PairWhitelist: already added");

        _whitelist[tokenIn][tokenOut] = true;
        emit PairAdded(tokenIn, tokenOut);
    }

    /**
     * @notice Remove a trading pair from the whitelist
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     */
    function removePair(address tokenIn, address tokenOut) external onlyTimelock {
        require(_whitelist[tokenIn][tokenOut], "PairWhitelist: not present");
        _whitelist[tokenIn][tokenOut] = false;
        emit PairRemoved(tokenIn, tokenOut);
    }

    /**
     * @notice Check if a trading pair is whitelisted
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @return bool True if whitelisted
     */
    function isPairWhitelisted(address tokenIn, address tokenOut) external view returns (bool) {
        return _whitelist[tokenIn][tokenOut];
    }
}
