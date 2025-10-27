// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Relay} from "../src/Relay.sol";
import {PairWhitelist} from "../src/PairWhitelist.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockSaucerswapRouter} from "../src/mocks/MockSaucerswapRouter.sol";
import {ParameterStore} from "../src/ParameterStore.sol";

contract RelayTest is Test {
    Relay public relay;
    PairWhitelist public pairWhitelist;
    Treasury public treasury;
    MockERC20 public htkToken;
    MockERC20 public usdcToken;
    MockERC20 public usdtToken;
    MockSaucerswapRouter public router;
    ParameterStore public parameterStore;

    address public dao;
    address public trader;
    address public unauthorized;

    uint256 constant INITIAL_SUPPLY = 1_000_000e6;
    uint256 constant MAX_TRADE_BPS = 1000; // 10%
    uint256 constant MAX_SLIPPAGE_BPS = 500; // 5%
    uint256 constant TRADE_COOLDOWN_SEC = 60; // 1 minute

    // Events
    event TradeProposed(
        address indexed trader,
        Relay.TradeType indexed tradeType,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 timestamp
    );

    event TradeRejected(
        address indexed trader,
        Relay.RejectionReason indexed reason,
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
        Relay.TradeType indexed tradeType,
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
        Relay.TradeType indexed tradeType,
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

    function setUp() public {
        dao = makeAddr("dao");
        trader = makeAddr("trader");
        unauthorized = makeAddr("unauthorized");

        // Deploy tokens
        htkToken = new MockERC20("HTK Token", "HTK", 6);
        usdcToken = new MockERC20("USDC Token", "USDC", 6);
        usdtToken = new MockERC20("USDT Token", "USDT", 6);

        // Deploy router
        router = new MockSaucerswapRouter();

        // Deploy PairWhitelist
        pairWhitelist = new PairWhitelist(dao);

        // Deploy Treasury
        treasury = new Treasury(address(htkToken), address(router), dao, address(this)); // temp relay

        // Deploy ParameterStore
        parameterStore = new ParameterStore(dao, MAX_TRADE_BPS, MAX_SLIPPAGE_BPS, TRADE_COOLDOWN_SEC);

        // Deploy Relay
        address[] memory initialTraders = new address[](1);
        initialTraders[0] = trader;
        relay = new Relay(
            address(pairWhitelist), address(treasury), address(router), address(parameterStore), dao, initialTraders
        );

        // Update Treasury to use Relay
        vm.prank(dao);
        treasury.updateRelay(address(this), address(relay));

        // Mint tokens
        htkToken.mint(address(router), INITIAL_SUPPLY);
        usdcToken.mint(address(treasury), 100_000e6);
        usdtToken.mint(address(treasury), 100_000e6);

        // Fund router with output tokens for swaps
        usdtToken.mint(address(router), INITIAL_SUPPLY);
        usdcToken.mint(address(router), INITIAL_SUPPLY);

        // Setup exchange rates (rate is scaled by 1e18)
        router.setExchangeRate(address(usdcToken), address(htkToken), 2e18); // 1 USDC = 2 HTK
        router.setExchangeRate(address(usdcToken), address(usdtToken), 1e18); // 1 USDC = 1 USDT (1:1)
    }

    /* ============ Deployment Tests ============ */

    function test_Deployment() public view {
        assertEq(address(relay.PAIR_WHITELIST()), address(pairWhitelist));
        assertEq(address(relay.TREASURY()), address(treasury));
        assertEq(parameterStore.maxTradeBps(), MAX_TRADE_BPS);
        assertEq(parameterStore.maxSlippageBps(), MAX_SLIPPAGE_BPS);
        assertEq(parameterStore.tradeCooldownSec(), TRADE_COOLDOWN_SEC);
        assertTrue(relay.hasRole(relay.TRADER_ROLE(), trader));
        assertTrue(relay.hasRole(relay.DAO_ROLE(), dao));
    }

    /* ============ Authorization Tests ============ */

    function test_AuthorizeTrader() public {
        address newTrader = makeAddr("newTrader");

        vm.expectEmit(true, false, false, true);
        emit TraderAuthorized(newTrader, block.timestamp);

        vm.prank(dao);
        relay.authorizeTrader(newTrader);

        assertTrue(relay.hasRole(relay.TRADER_ROLE(), newTrader));
    }

    function test_RevokeTrader() public {
        vm.expectEmit(true, false, false, true);
        emit TraderRevoked(trader, block.timestamp);

        vm.prank(dao);
        relay.revokeTrader(trader);

        assertFalse(relay.hasRole(relay.TRADER_ROLE(), trader));
    }

    function test_RevertIf_UnauthorizedAuthorizeTrader() public {
        address newTrader = makeAddr("newTrader");

        vm.prank(unauthorized);
        vm.expectRevert();
        relay.authorizeTrader(newTrader);
    }

    function test_RevertIf_AuthorizeZeroAddress() public {
        vm.prank(dao);
        vm.expectRevert("Relay: Invalid trader");
        relay.authorizeTrader(address(0));
    }

    /* ============ Parameter Update Tests ============ */

    function test_SetMaxTradeBps() public {
        uint256 newValue = 2000;

        vm.expectEmit(false, false, false, true);
        emit MaxTradeBpsUpdated(MAX_TRADE_BPS, newValue, block.timestamp);

        vm.prank(dao);
        parameterStore.setMaxTradeBps(newValue);

        assertEq(parameterStore.maxTradeBps(), newValue);
    }

    function test_RevertIf_SetMaxTradeBpsInvalid() public {
        vm.prank(dao);
        vm.expectRevert("ParameterStore: invalid maxTradeBps");
        parameterStore.setMaxTradeBps(10001);
    }

    function test_SetMaxSlippageBps() public {
        uint256 newValue = 1000;

        vm.expectEmit(false, false, false, true);
        emit MaxSlippageBpsUpdated(MAX_SLIPPAGE_BPS, newValue, block.timestamp);

        vm.prank(dao);
        parameterStore.setMaxSlippageBps(newValue);

        assertEq(parameterStore.maxSlippageBps(), newValue);
    }

    function test_SetTradeCooldownSec() public {
        uint256 newValue = 120;

        vm.expectEmit(false, false, false, true);
        emit TradeCooldownSecUpdated(TRADE_COOLDOWN_SEC, newValue, block.timestamp);

        vm.prank(dao);
        parameterStore.setTradeCooldownSec(newValue);

        assertEq(parameterStore.tradeCooldownSec(), newValue);
    }

    /* ============ Pair Whitelist Enforcement Tests ============ */

    function test_RevertIf_PairNotWhitelisted() public {
        vm.prank(trader);
        vm.expectRevert(
            abi.encodeWithSelector(Relay.PairNotWhitelisted.selector, address(usdcToken), address(usdtToken))
        );
        relay.proposeSwap(address(usdcToken), address(usdtToken), 1000e6, 990e6, block.timestamp + 1000);
    }

    function test_ProposeSwap_Success() public {
        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        uint256 amountIn = 1000e6;
        uint256 minAmountOut = 990e6;

        vm.expectEmit(true, true, true, false);
        emit TradeProposed(
            trader, Relay.TradeType.SWAP, address(usdcToken), address(usdtToken), amountIn, minAmountOut, 0
        );

        vm.prank(trader);
        uint256 amountOut =
            relay.proposeSwap(address(usdcToken), address(usdtToken), amountIn, minAmountOut, block.timestamp + 1000);

        assertGt(amountOut, 0);
    }

    /* ============ Max Trade Size Enforcement Tests ============ */

    function test_RevertIf_ExceedsMaxTradeSize() public {
        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        uint256 treasuryBalance = treasury.getBalance(address(usdcToken));
        uint256 maxAllowed = (treasuryBalance * MAX_TRADE_BPS) / 10000;
        uint256 excessiveAmount = maxAllowed + 1;

        vm.prank(trader);
        vm.expectRevert(
            abi.encodeWithSelector(Relay.ExceedsMaxTradeSize.selector, excessiveAmount, maxAllowed, MAX_TRADE_BPS)
        );
        relay.proposeSwap(address(usdcToken), address(usdtToken), excessiveAmount, 1e6, block.timestamp + 1000);
    }

    function test_ProposeSwap_AtMaxTradeSize() public {
        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        uint256 treasuryBalance = treasury.getBalance(address(usdcToken));
        uint256 maxAllowed = (treasuryBalance * MAX_TRADE_BPS) / 10000;

        vm.prank(trader);
        relay.proposeSwap(
            address(usdcToken), address(usdtToken), maxAllowed, maxAllowed * 95 / 100, block.timestamp + 1000
        );
    }

    /* ============ Slippage Enforcement Tests ============ */

    function test_RevertIf_ExceedsMaxSlippage() public {
        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        uint256 amountIn = 1000e6;
        // Set minAmountOut to 90% of amountIn = 10% slippage (1000 bps) > MAX_SLIPPAGE_BPS (500)
        uint256 minAmountOut = (amountIn * 90) / 100;

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Relay.ExceedsMaxSlippage.selector, 1000, MAX_SLIPPAGE_BPS));
        relay.proposeSwap(address(usdcToken), address(usdtToken), amountIn, minAmountOut, block.timestamp + 1000);
    }

    function test_ProposeSwap_WithinSlippageTolerance() public {
        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        uint256 amountIn = 1000e6;
        // Set minAmountOut to 96% of amountIn = 4% slippage (400 bps) < MAX_SLIPPAGE_BPS (500)
        uint256 minAmountOut = (amountIn * 96) / 100;

        vm.prank(trader);
        relay.proposeSwap(address(usdcToken), address(usdtToken), amountIn, minAmountOut, block.timestamp + 1000);
    }

    /* ============ Cooldown Enforcement Tests ============ */

    function test_RevertIf_CooldownNotElapsed() public {
        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        uint256 amountIn = 1000e6;
        uint256 minAmountOut = 990e6;

        // First trade
        vm.prank(trader);
        relay.proposeSwap(address(usdcToken), address(usdtToken), amountIn, minAmountOut, block.timestamp + 1000);

        // Immediate second trade (should fail)
        vm.prank(trader);
        vm.expectRevert(
            abi.encodeWithSelector(Relay.CooldownNotElapsed.selector, TRADE_COOLDOWN_SEC, TRADE_COOLDOWN_SEC)
        );
        relay.proposeSwap(address(usdcToken), address(usdtToken), amountIn, minAmountOut, block.timestamp + 1000);
    }

    function test_ProposeSwap_AfterCooldown() public {
        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        uint256 amountIn = 1000e6;
        uint256 minAmountOut = 990e6;

        // First trade
        vm.prank(trader);
        relay.proposeSwap(address(usdcToken), address(usdtToken), amountIn, minAmountOut, block.timestamp + 1000);

        // Advance time past cooldown
        vm.warp(block.timestamp + TRADE_COOLDOWN_SEC + 1);

        // Second trade (should succeed)
        vm.prank(trader);
        relay.proposeSwap(address(usdcToken), address(usdtToken), amountIn, minAmountOut, block.timestamp + 1000);
    }

    function test_GetCooldownRemaining() public {
        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        assertEq(relay.getCooldownRemaining(), 0);

        // Execute trade
        vm.prank(trader);
        relay.proposeSwap(address(usdcToken), address(usdtToken), 1000e6, 990e6, block.timestamp + 1000);

        assertEq(relay.getCooldownRemaining(), TRADE_COOLDOWN_SEC);

        vm.warp(block.timestamp + 30);
        assertEq(relay.getCooldownRemaining(), TRADE_COOLDOWN_SEC - 30);

        vm.warp(block.timestamp + TRADE_COOLDOWN_SEC);
        assertEq(relay.getCooldownRemaining(), 0);
    }

    /* ============ Buyback and Burn Tests ============ */

    function test_ProposeBuybackAndBurn_Success() public {
        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(htkToken));

        uint256 amountIn = 1000e6;
        uint256 minAmountOut = 1900e6; // Expect ~2000 HTK (allowing 5% slippage)

        vm.expectEmit(true, true, true, false);
        emit TradeProposed(
            trader, Relay.TradeType.BUYBACK_AND_BURN, address(usdcToken), address(htkToken), amountIn, minAmountOut, 0
        );

        vm.prank(trader);
        uint256 burnedAmount =
            relay.proposeBuybackAndBurn(address(usdcToken), amountIn, minAmountOut, block.timestamp + 1000);

        assertGt(burnedAmount, 0);
    }

    function test_RevertIf_BuybackPairNotWhitelisted() public {
        vm.prank(trader);
        vm.expectRevert(
            abi.encodeWithSelector(Relay.PairNotWhitelisted.selector, address(usdcToken), address(htkToken))
        );
        relay.proposeBuybackAndBurn(address(usdcToken), 1000e6, 1900e6, block.timestamp + 1000);
    }

    /* ============ Invalid Parameters Tests ============ */

    function test_RevertIf_ZeroAmountIn() public {
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        vm.prank(trader);
        vm.expectRevert(Relay.InvalidParameters.selector);
        relay.proposeSwap(address(usdcToken), address(usdtToken), 0, 100e6, block.timestamp + 1000);
    }

    function test_RevertIf_ZeroMinAmountOut() public {
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        vm.prank(trader);
        vm.expectRevert(Relay.InvalidParameters.selector);
        relay.proposeSwap(address(usdcToken), address(usdtToken), 1000e6, 0, block.timestamp + 1000);
    }

    /* ============ Insufficient Treasury Balance Tests ============ */

    function test_RevertIf_InsufficientTreasuryBalance() public {
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        uint256 treasuryBalance = treasury.getBalance(address(usdcToken));
        uint256 excessiveAmount = treasuryBalance + 1;

        vm.prank(trader);
        vm.expectRevert(
            abi.encodeWithSelector(Relay.InsufficientTreasuryBalance.selector, treasuryBalance, excessiveAmount)
        );
        relay.proposeSwap(address(usdcToken), address(usdtToken), excessiveAmount, 1e6, block.timestamp + 1000);
    }

    /* ============ Unauthorized Trader Tests ============ */

    function test_RevertIf_UnauthorizedTrader() public {
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        vm.prank(unauthorized);
        vm.expectRevert();
        relay.proposeSwap(address(usdcToken), address(usdtToken), 1000e6, 990e6, block.timestamp + 1000);
    }

    /* ============ Risk Parameters View Tests ============ */

    function test_GetRiskParameters() public view {
        (uint256 maxTrade, uint256 maxSlip, uint256 cooldown, uint256 lastTrade) = relay.getRiskParameters();

        assertEq(maxTrade, MAX_TRADE_BPS);
        assertEq(maxSlip, MAX_SLIPPAGE_BPS);
        assertEq(cooldown, TRADE_COOLDOWN_SEC);
        assertEq(lastTrade, 0);
    }

    /* ============ Event Emission Tests ============ */

    function test_EventEmission_FullTradeFlow() public {
        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        uint256 amountIn = 1000e6;
        uint256 minAmountOut = 990e6;

        // Expect all events
        vm.expectEmit(true, true, true, false);
        emit TradeProposed(
            trader, Relay.TradeType.SWAP, address(usdcToken), address(usdtToken), amountIn, minAmountOut, 0
        );

        vm.expectEmit(true, true, true, false);
        emit TradeApproved(
            trader,
            Relay.TradeType.SWAP,
            address(usdcToken),
            address(usdtToken),
            amountIn,
            minAmountOut,
            treasury.getBalance(address(usdcToken)),
            MAX_TRADE_BPS,
            MAX_SLIPPAGE_BPS,
            0
        );

        vm.expectEmit(true, true, true, false);
        emit TradeForwarded(trader, Relay.TradeType.SWAP, address(usdcToken), address(usdtToken), amountIn, 0, 0);

        vm.prank(trader);
        relay.proposeSwap(address(usdcToken), address(usdtToken), amountIn, minAmountOut, block.timestamp + 1000);
    }

    /* ============ Multiple Traders Tests ============ */

    function test_MultipleTradersAuthorized() public {
        address trader2 = makeAddr("trader2");

        vm.prank(dao);
        relay.authorizeTrader(trader2);

        assertTrue(relay.hasRole(relay.TRADER_ROLE(), trader));
        assertTrue(relay.hasRole(relay.TRADER_ROLE(), trader2));

        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        // Both traders can trade (respecting cooldown)
        vm.prank(trader);
        relay.proposeSwap(address(usdcToken), address(usdtToken), 1000e6, 990e6, block.timestamp + 1000);

        vm.warp(block.timestamp + TRADE_COOLDOWN_SEC + 1);

        vm.prank(trader2);
        relay.proposeSwap(address(usdcToken), address(usdtToken), 1000e6, 990e6, block.timestamp + 1000);
    }

    /* ============ Edge Cases ============ */

    function test_ProposeSwap_WithZeroCooldown() public {
        // Set cooldown to 0
        vm.prank(dao);
        parameterStore.setTradeCooldownSec(0);

        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        // Execute multiple trades immediately
        vm.startPrank(trader);
        relay.proposeSwap(address(usdcToken), address(usdtToken), 1000e6, 990e6, block.timestamp + 1000);
        relay.proposeSwap(address(usdcToken), address(usdtToken), 1000e6, 990e6, block.timestamp + 1000);
        vm.stopPrank();
    }

    function test_ProposeSwap_With100PercentMaxTrade() public {
        // Set max trade to 100%
        vm.prank(dao);
        parameterStore.setMaxTradeBps(10000);

        // Whitelist pair
        vm.prank(dao);
        pairWhitelist.addPair(address(usdcToken), address(usdtToken));

        uint256 treasuryBalance = treasury.getBalance(address(usdcToken));

        vm.prank(trader);
        relay.proposeSwap(
            address(usdcToken), address(usdtToken), treasuryBalance, treasuryBalance * 95 / 100, block.timestamp + 1000
        );
    }
}
