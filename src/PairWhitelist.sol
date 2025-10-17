// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

/**
 * @title PairWhitelist
 * @notice Manages whitelist of allowed trading pairs for Treasury operations
 * @dev DAO-controlled, enforces which token pairs can be traded via Relay
 */
contract PairWhitelist is AccessControl {
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");

    // Mapping: tokenIn => tokenOut => isWhitelisted
    mapping(address => mapping(address => bool)) private _whitelist;

    // Events
    event PairWhitelisted(address indexed tokenIn, address indexed tokenOut, uint256 timestamp);
    event PairBlacklisted(address indexed tokenIn, address indexed tokenOut, uint256 timestamp);

    /**
     * @notice Constructor
     * @param _admin Address of the admin (DAO multisig)
     */
    constructor(address _admin) {
        require(_admin != address(0), "PairWhitelist: Invalid admin");
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DAO_ROLE, _admin);
    }

    /**
     * @notice Whitelist a trading pair
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     */
    function whitelistPair(address tokenIn, address tokenOut) external onlyRole(DAO_ROLE) {
        require(tokenIn != address(0) && tokenOut != address(0), "PairWhitelist: Invalid tokens");
        require(tokenIn != tokenOut, "PairWhitelist: Same token");
        require(!_whitelist[tokenIn][tokenOut], "PairWhitelist: Already whitelisted");

        _whitelist[tokenIn][tokenOut] = true;
        emit PairWhitelisted(tokenIn, tokenOut, block.timestamp);
    }

    /**
     * @notice Blacklist a trading pair
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     */
    function blacklistPair(address tokenIn, address tokenOut) external onlyRole(DAO_ROLE) {
        require(_whitelist[tokenIn][tokenOut], "PairWhitelist: Not whitelisted");

        _whitelist[tokenIn][tokenOut] = false;
        emit PairBlacklisted(tokenIn, tokenOut, block.timestamp);
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

    /**
     * @notice Batch whitelist multiple pairs
     * @param tokensIn Array of input token addresses
     * @param tokensOut Array of output token addresses
     */
    function whitelistPairsBatch(address[] calldata tokensIn, address[] calldata tokensOut)
        external
        onlyRole(DAO_ROLE)
    {
        require(tokensIn.length == tokensOut.length, "PairWhitelist: Length mismatch");

        for (uint256 i = 0; i < tokensIn.length; i++) {
            address tokenIn = tokensIn[i];
            address tokenOut = tokensOut[i];

            require(tokenIn != address(0) && tokenOut != address(0), "PairWhitelist: Invalid tokens");
            require(tokenIn != tokenOut, "PairWhitelist: Same token");

            if (!_whitelist[tokenIn][tokenOut]) {
                _whitelist[tokenIn][tokenOut] = true;
                emit PairWhitelisted(tokenIn, tokenOut, block.timestamp);
            }
        }
    }
}
