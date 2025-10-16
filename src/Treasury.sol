// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {SafeERC20, IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Treasury
 * @notice Treasury contract that holds funds, executes buyback-and-burn operations
 * @dev Only accepts execution requests via the Relay contract
 */
contract Treasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant RELAY_ROLE = keccak256("RELAY_ROLE");
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");

    // HTK token address (governance token to be burned)
    address public immutable HTK_TOKEN;

    // Saucerswap Router interface
    ISaucerswapRouter public immutable SAUCERSWAP_ROUTER;

    // Events
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

    /**
     * @notice Constructor to initialize the Treasury
     * @param _htkToken Address of the HTK governance token
     * @param _saucerswapRouter Address of Saucerswap router
     * @param _admin Address of the admin (DAO multisig)
     * @param _relay Address of the Relay contract
     */
    constructor(
        address _htkToken,
        address _saucerswapRouter,
        address _admin,
        address _relay
    ) {
        require(_htkToken != address(0), "Treasury: Invalid HTK token");
        require(_saucerswapRouter != address(0), "Treasury: Invalid router");
        require(_admin != address(0), "Treasury: Invalid admin");
        require(_relay != address(0), "Treasury: Invalid relay");

        HTK_TOKEN = _htkToken;
        SAUCERSWAP_ROUTER = ISaucerswapRouter(_saucerswapRouter);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DAO_ROLE, _admin);
        _grantRole(RELAY_ROLE, _relay);
    }

    /**
     * @notice Deposit HTS tokens into the treasury
     * @param token Address of the token to deposit
     * @param amount Amount of tokens to deposit
     */
    function deposit(address token, uint256 amount) external nonReentrant {
        require(token != address(0), "Treasury: Invalid token");
        require(amount > 0, "Treasury: Zero amount");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(token, msg.sender, amount, block.timestamp);
    }

    /**
     * @notice Withdraw tokens from treasury (DAO only)
     * @param token Address of the token to withdraw
     * @param recipient Address to receive the tokens
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(
        address token,
        address recipient,
        uint256 amount
    ) external onlyRole(DAO_ROLE) nonReentrant {
        require(token != address(0), "Treasury: Invalid token");
        require(recipient != address(0), "Treasury: Invalid recipient");
        require(amount > 0, "Treasury: Zero amount");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance >= amount, "Treasury: Insufficient balance");

        IERC20(token).safeTransfer(recipient, amount);

        emit Withdrawn(token, recipient, amount, msg.sender, block.timestamp);
    }

    /**
     * @notice Execute buyback-and-burn operation
     * @dev Only callable by Relay contract
     * @param tokenIn Address of the token to swap for HTK
     * @param amountIn Amount of tokenIn to swap
     * @param amountOutMin Minimum amount of HTK to receive
     * @param deadline Deadline for the swap
     */
    function executeBuybackAndBurn(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external onlyRole(RELAY_ROLE) nonReentrant returns (uint256 burnedAmount) {
        require(tokenIn != address(0), "Treasury: Invalid token");
        require(tokenIn != HTK_TOKEN, "Treasury: Cannot swap HTK for HTK");
        require(amountIn > 0, "Treasury: Zero amount");
        require(deadline >= block.timestamp, "Treasury: Expired deadline");

        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        require(balance >= amountIn, "Treasury: Insufficient balance");

        // Execute buyback
        uint256 htkReceived = _buyback(tokenIn, amountIn, amountOutMin, deadline);

        emit BuybackExecuted(
            tokenIn,
            amountIn,
            htkReceived,
            msg.sender,
            block.timestamp
        );

        // Burn HTK
        burnedAmount = _burn(htkReceived);

        return burnedAmount;
    }

    /**
     * @notice Execute buyback without immediate burn (for flexibility)
     * @dev Only callable by Relay contract
     * @param tokenIn Address of the token to swap for HTK
     * @param amountIn Amount of tokenIn to swap
     * @param amountOutMin Minimum amount of HTK to receive
     * @param deadline Deadline for the swap
     */
    function executeBuyback(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external onlyRole(RELAY_ROLE) nonReentrant returns (uint256 htkReceived) {
        require(tokenIn != address(0), "Treasury: Invalid token");
        require(tokenIn != HTK_TOKEN, "Treasury: Cannot swap HTK for HTK");
        require(amountIn > 0, "Treasury: Zero amount");
        require(deadline >= block.timestamp, "Treasury: Expired deadline");

        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        require(balance >= amountIn, "Treasury: Insufficient balance");

        htkReceived = _buyback(tokenIn, amountIn, amountOutMin, deadline);

        emit BuybackExecuted(
            tokenIn,
            amountIn,
            htkReceived,
            msg.sender,
            block.timestamp
        );

        return htkReceived;
    }

    /**
     * @notice Burn accumulated HTK tokens
     * @dev Only callable by Relay contract
     * @param amount Amount of HTK to burn (0 = burn all)
     */
    function burn(uint256 amount) external onlyRole(RELAY_ROLE) nonReentrant returns (uint256 burnedAmount) {
        uint256 htkBalance = IERC20(HTK_TOKEN).balanceOf(address(this));

        if (amount == 0) {
            burnedAmount = htkBalance;
        } else {
            require(htkBalance >= amount, "Treasury: Insufficient HTK balance");
            burnedAmount = amount;
        }

        require(burnedAmount > 0, "Treasury: Nothing to burn");

        burnedAmount = _burn(burnedAmount);

        return burnedAmount;
    }

    /**
     * @notice Get token balance in treasury
     * @param token Address of the token
     * @return balance Token balance
     */
    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Update Relay contract address
     * @dev Only callable by DAO
     * @param oldRelay Address of old relay to revoke
     * @param newRelay Address of new relay to grant
     */
    function updateRelay(address oldRelay, address newRelay)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newRelay != address(0), "Treasury: Invalid relay");
        require(oldRelay != newRelay, "Treasury: Same relay");

        _revokeRole(RELAY_ROLE, oldRelay);
        _grantRole(RELAY_ROLE, newRelay);

        emit RelayUpdated(oldRelay, newRelay, block.timestamp);
    }

    /**
     * @dev Internal function to execute buyback via Saucerswap
     */
    function _buyback(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) private returns (uint256 htkReceived) {
        // Approve router to spend tokens
        IERC20(tokenIn).forceApprove(address(SAUCERSWAP_ROUTER), amountIn);

        // Prepare swap path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = HTK_TOKEN;

        uint256 htkBefore = IERC20(HTK_TOKEN).balanceOf(address(this));

        // Execute swap
        SAUCERSWAP_ROUTER.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );

        uint256 htkAfter = IERC20(HTK_TOKEN).balanceOf(address(this));
        htkReceived = htkAfter - htkBefore;

        require(htkReceived >= amountOutMin, "Treasury: Insufficient output");

        return htkReceived;
    }

    /**
     * @dev Internal function to burn HTK tokens
     */
    function _burn(uint256 amount) private returns (uint256) {
        require(amount > 0, "Treasury: Zero burn amount");

        // Burn by sending to dead address
        IERC20(HTK_TOKEN).safeTransfer(address(0xdead), amount);

        emit Burned(amount, msg.sender, block.timestamp);

        return amount;
    }
}

/**
 * @notice Minimal Saucerswap Router interface
 */
interface ISaucerswapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}