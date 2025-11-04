// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {PairWhitelist} from "./PairWhitelist.sol";
import {Treasury} from "./Treasury.sol";
import {ISaucerswapRouter} from "./interfaces/ISaucerswapRouter.sol";
import {ParameterStore} from "./ParameterStore.sol";
import {ITradeValidator} from "./interfaces/ITradeValidator.sol";

/**
 * @title Relay
 * @notice Validates and relays trade requests to Treasury with comprehensive DAO-controlled rules
 */
contract Relay is AccessControl, ReentrancyGuard {
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");
    bytes32 public constant TRADER_ROLE = keccak256("TRADER_ROLE");

    // Contracts
    PairWhitelist public immutable PAIR_WHITELIST;
    Treasury public immutable TREASURY;
    ISaucerswapRouter public immutable SAUCERSWAP_ROUTER;
    ParameterStore public immutable PARAM_STORE;

    // State tracking
    uint256 public lastTradeTimestamp;
    ITradeValidator[] public VALIDATORS;

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

    struct ValidationResult {
        bool isValid;
        uint256 maxTradeBps;
        uint256 maxSlippageBps;
        uint256 tradeCooldownSec;
        uint256 cooldownRemaining;
        uint256 treasuryBalance;
        uint256 impliedSlippage;
        uint256 maxAllowedAmount;
        RejectionReason[] reasons;
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

    event TradeValidationFailed(
        address indexed trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 maxTradeBps,
        uint256 maxSlippageBps,
        uint256 cooldownRemaining,
        RejectionReason[] reasons,
        uint256 timestamp
    );

    function addValidator(address validator) external onlyRole(DAO_ROLE) {
        require(validator != address(0), "Relay: invalid validator");
        VALIDATORS.push(ITradeValidator(validator));
    }

    function removeValidator(uint256 index) external onlyRole(DAO_ROLE) {
        require(index < VALIDATORS.length, "Relay: index OOB");
        VALIDATORS[index] = VALIDATORS[VALIDATORS.length - 1];
        VALIDATORS.pop();
    }

    /**
     * @notice Constructor
     * @param _pairWhitelist Address of PairWhitelist contract
     * @param _treasury Address of Treasury contract
     * @param _saucerswapRouter Address of Saucerswap router
     * @param _parameterStore Address of ParameterStore contract
     * @param _admin Address of admin (DAO multisig)
     * @param _initialTraders Array of initial authorized trader addresses
     */
    constructor(
        address _pairWhitelist,
        address _treasury,
        address _saucerswapRouter,
        address _parameterStore,
        address _admin,
        address[] memory _initialTraders
    ) {
        require(_pairWhitelist != address(0), "Relay: Invalid whitelist");
        require(_treasury != address(0), "Relay: Invalid treasury");
        require(_saucerswapRouter != address(0), "Relay: Invalid router");
        require(_parameterStore != address(0), "Relay: Invalid parameter store");
        require(_admin != address(0), "Relay: Invalid admin");
        require(_initialTraders.length > 0, "Relay: No initial traders");

        PAIR_WHITELIST = PairWhitelist(_pairWhitelist);
        TREASURY = Treasury(_treasury);
        SAUCERSWAP_ROUTER = ISaucerswapRouter(_saucerswapRouter);
        PARAM_STORE = ParameterStore(_parameterStore);

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
        returns (uint256 amountOut, RejectionReason[] reasons)
    {
        emit TradeProposed(msg.sender, TradeType.SWAP, tokenIn, tokenOut, amountIn, minAmountOut, block.timestamp);

        // Validate all rules (non-reverting)
        ValidationResult memory vr = _validateTrade(tokenIn, tokenOut, amountIn, minAmountOut);
        if (!vr.isValid) {
            emit TradeValidationFailed(
                msg.sender,
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut,
                vr.maxTradeBps,
                vr.maxSlippageBps,
                vr.cooldownRemaining,
                vr.reasons,
                block.timestamp
            );
            return (0, vr.reasons);
        }

        uint256 _maxTradeBps = vr.maxTradeBps;
        uint256 _maxSlippageBps = vr.maxSlippageBps;
        emit TradeApproved(
            msg.sender,
            TradeType.SWAP,
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            TREASURY.getBalance(tokenIn),
            _maxTradeBps,
            _maxSlippageBps,
            block.timestamp
        );

        // Update cooldown
        lastTradeTimestamp = block.timestamp;

        // Forward to Treasury
        amountOut = TREASURY.executeSwap(tokenIn, tokenOut, amountIn, minAmountOut, deadline);

        emit TradeForwarded(msg.sender, TradeType.SWAP, tokenIn, tokenOut, amountIn, amountOut, block.timestamp);

        return (amountOut, []);
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
        returns (uint256 burnedAmount, RejectionReason[] reasons)
    {
        address htkToken = TREASURY.HTK_TOKEN();

        emit TradeProposed(
            msg.sender, TradeType.BUYBACK_AND_BURN, tokenIn, htkToken, amountIn, minAmountOut, block.timestamp
        );

        // Validate all rules (non-reverting)
        ValidationResult memory vr = _validateTrade(tokenIn, htkToken, amountIn, minAmountOut);
        if (!vr.isValid) {
            emit TradeValidationFailed(
                msg.sender,
                tokenIn,
                htkToken,
                amountIn,
                minAmountOut,
                vr.maxTradeBps,
                vr.maxSlippageBps,
                vr.cooldownRemaining,
                vr.reasons,
                block.timestamp
            );
            return (0, vr.reasons);
        }

        uint256 _maxTradeBps = vr.maxTradeBps;
        uint256 _maxSlippageBps = vr.maxSlippageBps;
        emit TradeApproved(
            msg.sender,
            TradeType.BUYBACK_AND_BURN,
            tokenIn,
            htkToken,
            amountIn,
            minAmountOut,
            TREASURY.getBalance(tokenIn),
            _maxTradeBps,
            _maxSlippageBps,
            block.timestamp
        );

        // Update cooldown
        lastTradeTimestamp = block.timestamp;

        // Forward to Treasury
        burnedAmount = TREASURY.executeBuybackAndBurn(tokenIn, amountIn, minAmountOut, deadline);

        emit TradeForwarded(
            msg.sender, TradeType.BUYBACK_AND_BURN, tokenIn, htkToken, amountIn, burnedAmount, block.timestamp
        );

        return (burnedAmount, vr.reasons);
    }

    /**
     * @notice Validate trade against all DAO rules
     * @dev Non-reverting: aggregates all violations and returns details
     */
    function _validateTrade(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
        private
        view
        returns (ValidationResult memory vr)
    {
        vr.maxTradeBps = PARAM_STORE.maxTradeBps();
        vr.maxSlippageBps = PARAM_STORE.maxSlippageBps();
        vr.tradeCooldownSec = PARAM_STORE.tradeCooldownSec();

        // cooldown calc
        if (lastTradeTimestamp > 0) {
            uint256 elapsed = block.timestamp - lastTradeTimestamp;
            if (elapsed < vr.tradeCooldownSec) {
                vr.cooldownRemaining = vr.tradeCooldownSec - elapsed;
            }
        }

        // snapshot external state for validators
        bool pairWhitelisted = PAIR_WHITELIST.isPairWhitelisted(tokenIn, tokenOut);
        vr.treasuryBalance = TREASURY.getBalance(tokenIn);
        vr.maxAllowedAmount = (vr.treasuryBalance * vr.maxTradeBps) / 10000;
        vr.impliedSlippage = _calculateImpliedSlippage(tokenIn, tokenOut, amountIn, minAmountOut);

        ITradeValidator.TradeContext memory ctx = ITradeValidator.TradeContext({
            maxTradeBps: vr.maxTradeBps,
            maxSlippageBps: vr.maxSlippageBps,
            tradeCooldownSec: vr.tradeCooldownSec,
            lastTradeTimestamp: lastTradeTimestamp,
            cooldownRemaining: vr.cooldownRemaining,
            treasuryBalance: vr.treasuryBalance,
            maxAllowedAmount: vr.maxAllowedAmount,
            impliedSlippage: vr.impliedSlippage,
            pairWhitelisted: pairWhitelisted
        });

        uint256 validatorsLen = VALIDATORS.length;
        RejectionReason[] memory tmp = new RejectionReason[](validatorsLen);
        uint256 reasonCount = 0;
        for (uint256 i = 0; i < validatorsLen; i++) {
            (bool ok, uint8 reasonCode) = VALIDATORS[i].validate(
                msg.sender, tokenIn, tokenOut, amountIn, minAmountOut, ctx
            );
            if (!ok) {
                if (reasonCode <= uint8(type(RejectionReason).max)) {
                    tmp[reasonCount++] = RejectionReason(reasonCode);
                }
            }
        }

        vr.reasons = new RejectionReason[](reasonCount);
        for (uint256 i = 0; i < reasonCount; i++) {
            vr.reasons[i] = tmp[i];
        }
        vr.isValid = (reasonCount == 0);
        return vr;
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
     * @notice Get current risk parameters snapshot
     */
    function getRiskParameters()
        external
        view
        returns (uint256 _maxTradeBps, uint256 _maxSlippageBps, uint256 _tradeCooldownSec, uint256 _lastTradeTimestamp)
    {
        return
            (
                PARAM_STORE.maxTradeBps(),
                PARAM_STORE.maxSlippageBps(),
                PARAM_STORE.tradeCooldownSec(),
                lastTradeTimestamp
            );
    }

    /**
     * @notice Get the maximum allowed trade amount for a given input token under current settings
     * @dev Computed as (Treasury balance of tokenIn) * maxTradeBps / 10000
     * @param tokenIn Address of input token
     * @return maxAllowedAmount Maximum amount allowed for a single trade
     */
    function getMaxAllowedTradeAmount(address tokenIn) external view returns (uint256 maxAllowedAmount) {
        uint256 treasuryBalance = TREASURY.getBalance(tokenIn);
        uint256 _maxTradeBps = PARAM_STORE.maxTradeBps();
        maxAllowedAmount = (treasuryBalance * _maxTradeBps) / 10000;
    }

    /**
     * @notice Calculate remaining cooldown time
     * @return remaining seconds until next trade allowed (0 if ready)
     */
    function getCooldownRemaining() external view returns (uint256) {
        if (lastTradeTimestamp == 0) return 0;
        uint256 tradeCooldownSec = PARAM_STORE.tradeCooldownSec();
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
