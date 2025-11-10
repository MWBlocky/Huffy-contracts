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

    struct Pair {
        address tokenIn;
        address tokenOut;
    }
    Pair[] private _allPairs;
    // 1-based index for pair position in _allPairs; 0 means not present
    mapping(address => mapping(address => uint256)) private _allPairsIndex;

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

        (address token0, address token1) = tokenIn < tokenOut
            ? (tokenIn, tokenOut)
            : (tokenOut, tokenIn);

        require(!_whitelist[token0][token1], "PairWhitelist: already added");

        _whitelist[token0][token1] = true;

        _allPairs.push(Pair({tokenIn: token0, tokenOut: token1}));
        _allPairsIndex[token0][token1] = _allPairs.length;

        emit PairAdded(token0, token1);
    }

    /**
     * @notice Remove a trading pair from the whitelist
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     */
    function removePair(address tokenIn, address tokenOut) external onlyTimelock {
        (address token0, address token1) = tokenIn < tokenOut
            ? (tokenIn, tokenOut)
            : (tokenOut, tokenIn);

        require(_whitelist[token0][token1], "PairWhitelist: not present");
        _whitelist[token0][token1] = false;

        // Update global pairs storage
        uint256 idxAll1b = _allPairsIndex[token0][token1];
        if (idxAll1b != 0) {
            uint256 indexAll = idxAll1b - 1;
            uint256 lastIndexAll = _allPairs.length - 1;
            if (indexAll != lastIndexAll) {
                Pair storage lastPair = _allPairs[lastIndexAll];
                _allPairs[indexAll] = lastPair;
                _allPairsIndex[lastPair.tokenIn][lastPair.tokenOut] = indexAll + 1;
            }
            _allPairs.pop();
            delete _allPairsIndex[token0][token1];
        }

        emit PairRemoved(token0, token1);
    }

    /**
     * @notice Check if a trading pair is whitelisted
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @return bool True if whitelisted
     */
    function isPairWhitelisted(address tokenIn, address tokenOut) external view returns (bool) {
        if (tokenIn == tokenOut || tokenIn == address(0) || tokenOut == address(0)) {
            return false;
        }
        (address token0, address token1) = tokenIn < tokenOut
            ? (tokenIn, tokenOut)
            : (tokenOut, tokenIn);
        return _whitelist[token0][token1];
    }


    /**
     * @notice Get all whitelisted pairs
     * @return pairs Array of all whitelisted (tokenIn, tokenOut) pairs
     */
    function getAllWhitelistedPairs() external view returns (Pair[] memory pairs) {
        uint256 len = _allPairs.length;
        pairs = new Pair[](len);
        for (uint256 i = 0; i < len; i++) {
            Pair storage p = _allPairs[i];
            pairs[i] = Pair({tokenIn: p.tokenIn, tokenOut: p.tokenOut});
        }
        return pairs;
    }
}
