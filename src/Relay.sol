// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {PairWhitelist} from "./PairWhitelist.sol";
import {Treasury} from "./Treasury.sol";
import {ISaucerswapRouter} from "./interfaces/ISaucerswapRouter.sol";

/**
 * @title Relay
 * @notice Validates and relays trade requests to Treasury with comprehensive DAO-controlled rules
 * @dev Enforces whitelisted pairs, position size caps, slippage limits, and cooldown periods
 */
contract Relay is AccessControl, ReentrancyGuard {
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");
    bytes32 public constant TRADER_ROLE = keccak256("TRADER_ROLE");

    // Contracts
    PairWhitelist public immutable PAIR_WHITELIST;
    Treasury public immutable TREASURY;
    ISaucerswapRouter public immutable SAUCERSWAP_ROUTER;

    // Risk parameters (DAO-controlled)
    uint256 public maxTradeBps; // Max trade size as % of Treasury balance (basis points, e.g., 1000 = 10%)
    uint256 public maxSlippageBps; // Max allowed slippage (basis points)
    uint256 public tradeCooldownSec; // Minimum seconds between trades

    // State tracking
    uint256 public lastTradeTimestamp;

    // Trade types
    enum TradeType {
        SWAP, // Generic swap
        BUYBACK_AND_BURN // Buyback HTK and burn
    }

    // Rejection reasons
    enum RejectionReason {
        PAIR_NOT_WHITELISTED,
        EXCEEDS_MAX_TRADE_SIZE,
        EXCEEDS_MAX_SLIPPAGE,
        COOLDOWN_NOT_ELAPSED,
        INSUFFICIENT_TREASURY_BALANCE,
        INVALID_PARAMETERS
    }

    // Events
    event TradeProposed(
        address indexed trader,
        TradeType indexed tradeType,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 timestamp
    );

    event TradeRejected(
        address indexed trader,
        RejectionReason indexed reason,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 maxTradeBps,
        uint256 maxSlippageBps,
        uint256 cooldownRemaining,
        uint256 timestamp
    );

    event TradeApproved(
        address indexed trader,
        TradeType indexed tradeType,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 treasuryBalance,
        uint256 maxTradeBps,
        uint256 maxSlippageBps,
        uint256 timestamp
    );

    event TradeForwarded(
        address indexed trader,
        TradeType indexed tradeType,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );

    event TraderAuthorized(address indexed trader, uint256 timestamp);
    event TraderRevoked(address indexed trader, uint256 timestamp);

    event MaxTradeBpsUpdated(uint256 oldValue, uint256 newValue, uint256 timestamp);
    event MaxSlippageBpsUpdated(uint256 oldValue, uint256 newValue, uint256 timestamp);
    event TradeCooldownSecUpdated(uint256 oldValue, uint256 newValue, uint256 timestamp);

    /**
     * @notice Constructor
     * @param _pairWhitelist Address of PairWhitelist contract
     * @param _treasury Address of Treasury contract
     * @param _saucerswapRouter Address of Saucerswap router
     * @param _admin Address of admin (DAO multisig)
     * @param _initialTraders Array of initial authorized trader addresses
     * @param _maxTradeBps Initial max trade size in basis points
     * @param _maxSlippageBps Initial max slippage in basis points
     * @param _tradeCooldownSec Initial cooldown period in seconds
     */
    constructor(
        address _pairWhitelist,
        address _treasury,
        address _saucerswapRouter,
        address _admin,
        address[] memory _initialTraders,
        uint256 _maxTradeBps,
        uint256 _maxSlippageBps,
        uint256 _tradeCooldownSec
    ) {
        require(_pairWhitelist != address(0), "Relay: Invalid whitelist");
        require(_treasury != address(0), "Relay: Invalid treasury");
        require(_saucerswapRouter != address(0), "Relay: Invalid router");
        require(_admin != address(0), "Relay: Invalid admin");
        require(_initialTraders.length > 0, "Relay: No initial traders");
        require(_maxTradeBps <= 10000, "Relay: Invalid maxTradeBps");
        require(_maxSlippageBps <= 10000, "Relay: Invalid maxSlippageBps");

        PAIR_WHITELIST = PairWhitelist(_pairWhitelist);
        TREASURY = Treasury(_treasury);
        SAUCERSWAP_ROUTER = ISaucerswapRouter(_saucerswapRouter);

        maxTradeBps = _maxTradeBps;
        maxSlippageBps = _maxSlippageBps;
        tradeCooldownSec = _tradeCooldownSec;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DAO_ROLE, _admin);

        for (uint256 i = 0; i < _initialTraders.length; i++) {
            require(_initialTraders[i] != address(0), "Relay: Invalid trader");
            _grantRole(TRADER_ROLE, _initialTraders[i]);
            emit TraderAuthorized(_initialTraders[i], block.timestamp);
        }
    }

    /**
     * @notice Submit a generic swap trade proposal
     * @param tokenIn Address of input token
     * @param tokenOut Address of output token
     * @param amountIn Amount of tokenIn to swap
     * @param minAmountOut Minimum amount of tokenOut expected
     * @param deadline Swap deadline timestamp
     * @return amountOut Actual amount received
     */
    function proposeSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        external
        onlyRole(TRADER_ROLE)
        nonReentrant
        returns (uint256 amountOut)
    {
        emit TradeProposed(msg.sender, TradeType.SWAP, tokenIn, tokenOut, amountIn, minAmountOut, block.timestamp);

        // Validate all rules
        _validateTrade(tokenIn, tokenOut, amountIn, minAmountOut);

        emit TradeApproved(
            msg.sender,
            TradeType.SWAP,
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            TREASURY.getBalance(tokenIn),
            maxTradeBps,
            maxSlippageBps,
            block.timestamp
        );

        // Update cooldown
        lastTradeTimestamp = block.timestamp;

        // Forward to Treasury
        amountOut = TREASURY.executeSwap(tokenIn, tokenOut, amountIn, minAmountOut, deadline);

        emit TradeForwarded(msg.sender, TradeType.SWAP, tokenIn, tokenOut, amountIn, amountOut, block.timestamp);

        return amountOut;
    }

    /**
     * @notice Submit a buyback-and-burn trade proposal
     * @param tokenIn Address of input token
     * @param amountIn Amount of tokenIn to swap for HTK
     * @param minAmountOut Minimum HTK to receive
     * @param deadline Swap deadline timestamp
     * @return burnedAmount Amount of HTK burned
     */
    function proposeBuybackAndBurn(address tokenIn, uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        external
        onlyRole(TRADER_ROLE)
        nonReentrant
        returns (uint256 burnedAmount)
    {
        address htkToken = TREASURY.HTK_TOKEN();

        emit TradeProposed(
            msg.sender, TradeType.BUYBACK_AND_BURN, tokenIn, htkToken, amountIn, minAmountOut, block.timestamp
        );

        // Validate all rules
        _validateTrade(tokenIn, htkToken, amountIn, minAmountOut);

        emit TradeApproved(
            msg.sender,
            TradeType.BUYBACK_AND_BURN,
            tokenIn,
            htkToken,
            amountIn,
            minAmountOut,
            TREASURY.getBalance(tokenIn),
            maxTradeBps,
            maxSlippageBps,
            block.timestamp
        );

        // Update cooldown
        lastTradeTimestamp = block.timestamp;

        // Forward to Treasury
        burnedAmount = TREASURY.executeBuybackAndBurn(tokenIn, amountIn, minAmountOut, deadline);

        emit TradeForwarded(
            msg.sender, TradeType.BUYBACK_AND_BURN, tokenIn, htkToken, amountIn, burnedAmount, block.timestamp
        );

        return burnedAmount;
    }

    /**
     * @notice Validate trade against all DAO rules
     * @dev Reverts on any rule violation with detailed event emission
     */
    function _validateTrade(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut) private view {
        // 1. Validate pair whitelist
        if (!PAIR_WHITELIST.isPairWhitelisted(tokenIn, tokenOut)) {
            revert PairNotWhitelisted(tokenIn, tokenOut);
        }

        // 2. Validate basic parameters
        if (tokenIn == address(0) || tokenOut == address(0) || amountIn == 0 || minAmountOut == 0) {
            revert InvalidParameters();
        }

        // 3. Check Treasury balance
        uint256 treasuryBalance = TREASURY.getBalance(tokenIn);
        if (treasuryBalance < amountIn) {
            revert InsufficientTreasuryBalance(treasuryBalance, amountIn);
        }

        // 4. Validate max trade size (maxTradeBps)
        uint256 maxAllowedAmount = (treasuryBalance * maxTradeBps) / 10000;
        if (amountIn > maxAllowedAmount) {
            revert ExceedsMaxTradeSize(amountIn, maxAllowedAmount, maxTradeBps);
        }

        // 5. Validate slippage (maxSlippageBps)
        uint256 impliedSlippage = _calculateImpliedSlippage(tokenIn, tokenOut, amountIn, minAmountOut);
        if (impliedSlippage > maxSlippageBps) {
            revert ExceedsMaxSlippage(impliedSlippage, maxSlippageBps);
        }

        // 6. Validate cooldown period
        if (lastTradeTimestamp > 0) {
            uint256 timeSinceLastTrade = block.timestamp - lastTradeTimestamp;
            if (timeSinceLastTrade < tradeCooldownSec) {
                revert CooldownNotElapsed(tradeCooldownSec - timeSinceLastTrade, tradeCooldownSec);
            }
        }
    }

    /**
     * @notice Calculate implied slippage by querying Saucerswap router
     * @dev Queries router for expected output and compares with minAmountOut
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input token
     * @param minAmountOut Minimum acceptable output amount (with slippage tolerance)
     * @return slippageBps Slippage in basis points
     */
    function _calculateImpliedSlippage(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
        private
        view
        returns (uint256 slippageBps)
    {
        // Build path for router query
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        // Query router for expected output (without slippage)
        uint256[] memory amounts = SAUCERSWAP_ROUTER.getAmountsOut(amountIn, path);
        uint256 expectedAmountOut = amounts[1];

        // If minAmountOut >= expected, no slippage (return 0)
        if (minAmountOut >= expectedAmountOut) {
            return 0;
        }

        // Calculate slippage: (expected - min) / expected * 10000
        uint256 slippageAmount = expectedAmountOut - minAmountOut;
        slippageBps = (slippageAmount * 10000) / expectedAmountOut;

        return slippageBps;
    }

    /**
     * @notice Authorize a new trader
     * @param trader Address of trader to authorize
     */
    function authorizeTrader(address trader) external onlyRole(DAO_ROLE) {
        require(trader != address(0), "Relay: Invalid trader");
        _grantRole(TRADER_ROLE, trader);
        emit TraderAuthorized(trader, block.timestamp);
    }

    /**
     * @notice Revoke trader authorization
     * @param trader Address of trader to revoke
     */
    function revokeTrader(address trader) external onlyRole(DAO_ROLE) {
        _revokeRole(TRADER_ROLE, trader);
        emit TraderRevoked(trader, block.timestamp);
    }

    /**
     * @notice Update maxTradeBps parameter
     * @param newMaxTradeBps New max trade size in basis points
     */
    function setMaxTradeBps(uint256 newMaxTradeBps) external onlyRole(DAO_ROLE) {
        require(newMaxTradeBps <= 10000, "Relay: Invalid maxTradeBps");
        uint256 oldValue = maxTradeBps;
        maxTradeBps = newMaxTradeBps;
        emit MaxTradeBpsUpdated(oldValue, newMaxTradeBps, block.timestamp);
    }

    /**
     * @notice Update maxSlippageBps parameter
     * @param newMaxSlippageBps New max slippage in basis points
     */
    function setMaxSlippageBps(uint256 newMaxSlippageBps) external onlyRole(DAO_ROLE) {
        require(newMaxSlippageBps <= 10000, "Relay: Invalid maxSlippageBps");
        uint256 oldValue = maxSlippageBps;
        maxSlippageBps = newMaxSlippageBps;
        emit MaxSlippageBpsUpdated(oldValue, newMaxSlippageBps, block.timestamp);
    }

    /**
     * @notice Update tradeCooldownSec parameter
     * @param newTradeCooldownSec New cooldown period in seconds
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
        returns (uint256 _maxTradeBps, uint256 _maxSlippageBps, uint256 _tradeCooldownSec, uint256 _lastTradeTimestamp)
    {
        return (maxTradeBps, maxSlippageBps, tradeCooldownSec, lastTradeTimestamp);
    }

    /**
     * @notice Get the maximum allowed trade amount for a given input token under current settings
     * @dev Computed as (Treasury balance of tokenIn) * maxTradeBps / 10000
     * @param tokenIn Address of input token
     * @return maxAllowedAmount Maximum amount allowed for a single trade
     */
    function getMaxAllowedTradeAmount(address tokenIn) external view returns (uint256 maxAllowedAmount) {
        uint256 treasuryBalance = TREASURY.getBalance(tokenIn);
        maxAllowedAmount = (treasuryBalance * maxTradeBps) / 10000;
    }

    /**
     * @notice Calculate remaining cooldown time
     * @return remaining seconds until next trade allowed (0 if ready)
     */
    function getCooldownRemaining() external view returns (uint256) {
        if (lastTradeTimestamp == 0) return 0;
        uint256 elapsed = block.timestamp - lastTradeTimestamp;
        if (elapsed >= tradeCooldownSec) return 0;
        return tradeCooldownSec - elapsed;
    }

    // Custom errors for gas efficiency and clarity
    error PairNotWhitelisted(address tokenIn, address tokenOut);
    error ExceedsMaxTradeSize(uint256 requested, uint256 maxAllowed, uint256 maxTradeBps);
    error ExceedsMaxSlippage(uint256 implied, uint256 maxAllowed);
    error CooldownNotElapsed(uint256 remaining, uint256 required);
    error InsufficientTreasuryBalance(uint256 available, uint256 requested);
    error InvalidParameters();
}
