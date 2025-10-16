// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockSaucerswapRouter} from "../src/mocks/MockSaucerswapRouter.sol";
import {MockRelay} from "../src/mocks/MockRelay.sol";
import {SafeERC20, IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessControl} from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract TreasuryTest is Test {
    using SafeERC20 for IERC20;
    Treasury public treasury;
    MockRelay public mockRelay;
    MockERC20 public htkToken;
    MockERC20 public usdcToken;
    MockSaucerswapRouter public saucerswapRouter;

    address public owner;
    address public dao;
    address public user1;
    address public user2;
    address public unauthorized;

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 constant EXCHANGE_RATE = 2e18; // 1 USDC = 2 HTK

    event Deposited(
        address indexed token,
        address indexed depositor,
        uint256 amount,
        uint256 timestamp
    );

    event Withdrawn(
        address indexed token,
        address indexed recipient,
        uint256 amount,
        address indexed initiator,
        uint256 timestamp
    );

    event BuybackExecuted(
        address indexed tokenIn,
        uint256 amountIn,
        uint256 htkReceived,
        address indexed initiator,
        uint256 timestamp
    );

    event Burned(
        uint256 amount,
        address indexed initiator,
        uint256 timestamp
    );

    event RelayUpdated(
        address indexed oldRelay,
        address indexed newRelay,
        uint256 timestamp
    );

    function setUp() public {
        owner = address(this);
        dao = makeAddr("dao");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        unauthorized = makeAddr("unauthorized");

        // Deploy mock tokens
        htkToken = new MockERC20("HTK Token", "HTK", 18);
        usdcToken = new MockERC20("USDC Token", "USDC", 6);

        // Deploy mock Saucerswap router
        saucerswapRouter = new MockSaucerswapRouter();

        // Deploy Treasury
        treasury = new Treasury(
            address(htkToken),
            address(saucerswapRouter),
            dao,
            owner // Initially use owner as relay
        );

        // Mint tokens
        htkToken.mint(owner, INITIAL_SUPPLY);
        htkToken.mint(address(saucerswapRouter), INITIAL_SUPPLY);
        usdcToken.mint(user1, 100_000e6);
        usdcToken.mint(address(treasury), 10_000e6);

        // Setup exchange rate
        saucerswapRouter.setExchangeRate(
            address(usdcToken),
            address(htkToken),
            EXCHANGE_RATE
        );

        // Deploy MockRelay
        mockRelay = new MockRelay(address(treasury));

        // Update relay in treasury
        vm.prank(dao);
        treasury.updateRelay(owner, address(mockRelay));
    }

    /* ============ Deployment Tests ============ */

    function test_Deployment() public view {
        assertEq(treasury.HTK_TOKEN(), address(htkToken));
        assertEq(address(treasury.SAUCERSWAP_ROUTER()), address(saucerswapRouter));

        bytes32 daoRole = treasury.DAO_ROLE();
        assertTrue(treasury.hasRole(daoRole, dao));

        bytes32 relayRole = treasury.RELAY_ROLE();
        assertTrue(treasury.hasRole(relayRole, address(mockRelay)));
    }

    function test_RevertWhen_DeployWithZeroHTKToken() public {
        vm.expectRevert(bytes("Treasury: Invalid HTK token"));
        new Treasury(
            address(0),
            address(saucerswapRouter),
            dao,
            owner
        );
    }

    function test_RevertWhen_DeployWithZeroRouter() public {
        vm.expectRevert(bytes("Treasury: Invalid router"));
        new Treasury(
            address(htkToken),
            address(0),
            dao,
            owner
        );
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert(bytes("Treasury: Invalid admin"));
        new Treasury(
            address(htkToken),
            address(saucerswapRouter),
            address(0),
            owner
        );
    }

    function test_RevertWhen_DeployWithZeroRelay() public {
        vm.expectRevert(bytes("Treasury: Invalid relay"));
        new Treasury(
            address(htkToken),
            address(saucerswapRouter),
            dao,
            address(0)
        );
    }

    /* ============ Deposit Tests ============ */

    function test_Deposit() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(user1);
        usdcToken.approve(address(treasury), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit Deposited(address(usdcToken), user1, depositAmount, block.timestamp);

        treasury.deposit(address(usdcToken), depositAmount);
        vm.stopPrank();

        assertEq(treasury.getBalance(address(usdcToken)), 11_000e6);
    }

    function testFuzz_Deposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100_000e6);

        vm.startPrank(user1);
        usdcToken.approve(address(treasury), amount);
        treasury.deposit(address(usdcToken), amount);
        vm.stopPrank();

        assertEq(treasury.getBalance(address(usdcToken)), 10_000e6 + amount);
    }

    function test_RevertWhen_DepositZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(bytes("Treasury: Zero amount"));
        treasury.deposit(address(usdcToken), 0);
    }

    function test_RevertWhen_DepositInvalidToken() public {
        vm.prank(user1);
        vm.expectRevert(bytes("Treasury: Invalid token"));
        treasury.deposit(address(0), 1000);
    }

    function test_MultipleDeposits() public {
        uint256 depositAmount1 = 1000e6;
        uint256 depositAmount2 = 500e6;

        vm.startPrank(user1);
        usdcToken.approve(address(treasury), depositAmount1);
        treasury.deposit(address(usdcToken), depositAmount1);

        usdcToken.approve(address(treasury), depositAmount2);
        treasury.deposit(address(usdcToken), depositAmount2);
        vm.stopPrank();

        assertEq(treasury.getBalance(address(usdcToken)), 11_500e6);
    }

    /* ============ Withdraw Tests ============ */

    function test_Withdraw() public {
        uint256 withdrawAmount = 1000e6;
        uint256 initialBalance = usdcToken.balanceOf(user2);

        vm.prank(dao);
        vm.expectEmit(true, true, false, true);
        emit Withdrawn(address(usdcToken), user2, withdrawAmount, dao, block.timestamp);

        treasury.withdraw(address(usdcToken), user2, withdrawAmount);

        assertEq(usdcToken.balanceOf(user2), initialBalance + withdrawAmount);
    }

    function testFuzz_Withdraw(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 10_000e6);

        vm.prank(dao);
        treasury.withdraw(address(usdcToken), user2, amount);

        assertEq(treasury.getBalance(address(usdcToken)), 10_000e6 - amount);
    }

    function test_RevertWhen_WithdrawByNonDAO() public {
        vm.prank(unauthorized);
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        treasury.withdraw(address(usdcToken), user2, 1000e6);
    }

    function test_RevertWhen_WithdrawInsufficientBalance() public {
        vm.prank(dao);
        vm.expectRevert(bytes("Treasury: Insufficient balance"));
        treasury.withdraw(address(usdcToken), user2, 20_000e6);
    }

    function test_RevertWhen_WithdrawZeroAmount() public {
        vm.prank(dao);
        vm.expectRevert(bytes("Treasury: Zero amount"));
        treasury.withdraw(address(usdcToken), user2, 0);
    }

    function test_RevertWhen_WithdrawInvalidToken() public {
        vm.prank(dao);
        vm.expectRevert(bytes("Treasury: Invalid token"));
        treasury.withdraw(address(0), user2, 1000);
    }

    function test_RevertWhen_WithdrawInvalidRecipient() public {
        vm.prank(dao);
        vm.expectRevert(bytes("Treasury: Invalid recipient"));
        treasury.withdraw(address(usdcToken), address(0), 1000);
    }

    /* ============ Buyback and Burn Tests ============ */

    function test_BuybackAndBurn() public {
        uint256 buybackAmount = 1000e6;
        uint256 expectedHtk = 2000e18; // 1000 USDC * 2 = 2000 HTK
        uint256 deadline = block.timestamp + 3600;

        vm.expectEmit(true, false, false, true);
        emit BuybackExecuted(
            address(usdcToken),
            buybackAmount,
            expectedHtk,
            address(mockRelay),
            block.timestamp
        );

        vm.expectEmit(false, false, false, true);
        emit Burned(expectedHtk, address(mockRelay), block.timestamp);

        mockRelay.executeBuybackAndBurn(
            address(usdcToken),
            buybackAmount,
            expectedHtk,
            deadline
        );

        // Check HTK was burned (sent to dead address)
        assertEq(htkToken.balanceOf(address(0xdead)), expectedHtk);
    }

    function testFuzz_BuybackAndBurn(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 10_000e6);

        // amount is in smallest units of USDC (6 decimals). Router computes
        // amountOut = amountIn * EXCHANGE_RATE / 10^decimals(tokenIn).
        // Since USDC has 6 decimals, divide by 1e6 here to match router logic.
        uint256 expectedHtk = (amount * EXCHANGE_RATE) / 1e6;
        uint256 deadline = block.timestamp + 3600;

        mockRelay.executeBuybackAndBurn(
            address(usdcToken),
            amount,
            expectedHtk,
            deadline
        );

        assertEq(htkToken.balanceOf(address(0xdead)), expectedHtk);
    }

    function test_RevertWhen_BuybackAndBurnByNonRelay() public {
        uint256 buybackAmount = 1000e6;
        uint256 expectedHtk = 2000e18;
        uint256 deadline = block.timestamp + 3600;

        vm.prank(unauthorized);
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        treasury.executeBuybackAndBurn(
            address(usdcToken),
            buybackAmount,
            expectedHtk,
            deadline
        );
    }

    function test_RevertWhen_BuybackHTKForHTK() public {
        uint256 buybackAmount = 1000e18;
        uint256 deadline = block.timestamp + 3600;

        vm.expectRevert(bytes("Treasury: Cannot swap HTK for HTK"));
        mockRelay.executeBuybackAndBurn(
            address(htkToken),
            buybackAmount,
            0,
            deadline
        );
    }

    function test_RevertWhen_BuybackExpiredDeadline() public {
        uint256 buybackAmount = 1000e6;
        uint256 deadline = block.timestamp - 1;

        vm.expectRevert(bytes("Treasury: Expired deadline"));
        mockRelay.executeBuybackAndBurn(
            address(usdcToken),
            buybackAmount,
            0,
            deadline
        );
    }

    function test_RevertWhen_BuybackInsufficientBalance() public {
        uint256 buybackAmount = 20_000e6;
        uint256 deadline = block.timestamp + 3600;

        vm.expectRevert(bytes("Treasury: Insufficient balance"));
        mockRelay.executeBuybackAndBurn(
            address(usdcToken),
            buybackAmount,
            0,
            deadline
        );
    }

    function test_BuybackWithoutBurn() public {
        uint256 buybackAmount = 1000e6;
        uint256 expectedHtk = 2000e18;
        uint256 deadline = block.timestamp + 3600;

        uint256 initialHtkBalance = treasury.getBalance(address(htkToken));

        vm.expectEmit(true, false, false, true);
        emit BuybackExecuted(
            address(usdcToken),
            buybackAmount,
            expectedHtk,
            address(mockRelay),
            block.timestamp
        );

        mockRelay.executeBuyback(
            address(usdcToken),
            buybackAmount,
            expectedHtk,
            deadline
        );

        // HTK should be in treasury, not burned yet
        assertEq(treasury.getBalance(address(htkToken)), initialHtkBalance + expectedHtk);
    }

    function test_BurnAccumulatedHTK() public {
        // First buyback without burn
        uint256 buybackAmount = 1000e6;
        uint256 expectedHtk = 2000e18;
        uint256 deadline = block.timestamp + 3600;

        mockRelay.executeBuyback(
            address(usdcToken),
            buybackAmount,
            expectedHtk,
            deadline
        );

        // Now burn
        vm.expectEmit(false, false, false, true);
        emit Burned(expectedHtk, address(mockRelay), block.timestamp);

        mockRelay.burn(expectedHtk);

        assertEq(htkToken.balanceOf(address(0xdead)), expectedHtk);
    }

    function test_BurnAllHTK() public {
        // Fund treasury with HTK
        uint256 htkAmount = 5000e18;
        IERC20(address(htkToken)).safeTransfer(address(treasury), htkAmount);

        vm.expectEmit(false, false, false, true);
        emit Burned(htkAmount, address(mockRelay), block.timestamp);

        mockRelay.burn(0); // 0 means burn all

        assertEq(htkToken.balanceOf(address(0xdead)), htkAmount);
    }

    /* ============ Access Control Tests ============ */

    function test_UpdateRelay() public {
        address newRelay = makeAddr("newRelay");

        vm.prank(dao);
        vm.expectEmit(true, true, false, true);
        emit RelayUpdated(address(mockRelay), newRelay, block.timestamp);

        treasury.updateRelay(address(mockRelay), newRelay);

        bytes32 relayRole = treasury.RELAY_ROLE();
        assertTrue(treasury.hasRole(relayRole, newRelay));
        assertFalse(treasury.hasRole(relayRole, address(mockRelay)));
    }

    function test_RevertWhen_UpdateRelayByNonAdmin() public {
        vm.prank(unauthorized);
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        treasury.updateRelay(address(mockRelay), user2);
    }

    function test_RevertWhen_UpdateRelaySameAddress() public {
        vm.prank(dao);
        vm.expectRevert(bytes("Treasury: Same relay"));
        treasury.updateRelay(address(mockRelay), address(mockRelay));
    }

    function test_RevertWhen_UpdateRelayZeroAddress() public {
        vm.prank(dao);
        vm.expectRevert(bytes("Treasury: Invalid relay"));
        treasury.updateRelay(address(mockRelay), address(0));
    }

    function test_RevertWhen_UnauthorizedExecuteBuybackAndBurn() public {
        uint256 buybackAmount = 1000e6;
        uint256 deadline = block.timestamp + 3600;

        vm.prank(unauthorized);
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        treasury.executeBuybackAndBurn(
            address(usdcToken),
            buybackAmount,
            0,
            deadline
        );
    }

    function test_RevertWhen_UnauthorizedExecuteBuyback() public {
        uint256 buybackAmount = 1000e6;
        uint256 deadline = block.timestamp + 3600;

        vm.prank(unauthorized);
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        treasury.executeBuyback(
            address(usdcToken),
            buybackAmount,
            0,
            deadline
        );
    }

    function test_RevertWhen_UnauthorizedBurn() public {
        vm.prank(unauthorized);
        vm.expectRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        treasury.burn(1000);
    }

    /* ============ Integration Tests ============ */

    function test_FullFlow_DepositBuybackBurn() public {
        // 1. User deposits USDC
        uint256 depositAmount = 5000e6;
        vm.startPrank(user1);
        usdcToken.approve(address(treasury), depositAmount);
        treasury.deposit(address(usdcToken), depositAmount);
        vm.stopPrank();

        // 2. Relay executes buyback and burn
        uint256 buybackAmount = 3000e6;
        uint256 expectedHtk = 6000e18;
        uint256 deadline = block.timestamp + 3600;

        mockRelay.executeBuybackAndBurn(
            address(usdcToken),
            buybackAmount,
            expectedHtk,
            deadline
        );

        // 3. Verify final state
        uint256 remainingUsdc = 12_000e6; // 10000 + 5000 - 3000
        assertEq(treasury.getBalance(address(usdcToken)), remainingUsdc);
        assertEq(htkToken.balanceOf(address(0xdead)), expectedHtk);
    }

    function test_MultipleBuybackOperations() public {
        uint256 buybackAmount1 = 1000e6;
        uint256 buybackAmount2 = 2000e6;
        uint256 deadline = block.timestamp + 3600;

        mockRelay.executeBuybackAndBurn(
            address(usdcToken),
            buybackAmount1,
            0,
            deadline
        );

        mockRelay.executeBuybackAndBurn(
            address(usdcToken),
            buybackAmount2,
            0,
            deadline
        );

        uint256 totalBurned = 6000e18; // (1000 + 2000) * 2
        assertEq(htkToken.balanceOf(address(0xdead)), totalBurned);
    }

    function test_SeparateBuybackAndBurn() public {
        uint256 buybackAmount = 1000e6;
        uint256 expectedHtk = 2000e18;
        uint256 deadline = block.timestamp + 3600;

        // Execute buyback
        mockRelay.executeBuyback(
            address(usdcToken),
            buybackAmount,
            expectedHtk,
            deadline
        );

        // Verify HTK in treasury
        assertEq(treasury.getBalance(address(htkToken)), expectedHtk);

        // Execute burn
        mockRelay.burn(expectedHtk);

        // Verify burned
        assertEq(htkToken.balanceOf(address(0xdead)), expectedHtk);
        assertEq(treasury.getBalance(address(htkToken)), 0);
    }

    /* ============ View Function Tests ============ */

    function test_GetBalance() public view {
        uint256 balance = treasury.getBalance(address(usdcToken));
        assertEq(balance, 10_000e6);
    }

    function test_GetBalanceZero() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        uint256 balance = treasury.getBalance(address(newToken));
        assertEq(balance, 0);
    }
}