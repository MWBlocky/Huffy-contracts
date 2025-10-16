// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Treasury} from "../Treasury.sol";

/**
 * @title MockDAO
 * @notice Minimal DAO mock to act as the Treasury admin (DAO). Provides helper methods
 *         to perform DAO-only actions on the Treasury. Useful for testing and
 *         having a concrete DAO address during deployments.
 */
contract MockDAO {
    address public owner;
    Treasury public treasury;

    event OwnerTransferred(address indexed previousOwner, address indexed newOwner);
    event TreasurySet(address indexed treasury);
    event DaoWithdraw(address indexed token, address indexed recipient, uint256 amount, address indexed caller);
    event DaoRelayUpdate(address indexed oldRelay, address indexed newRelay, address indexed caller);

    modifier onlyOwner() {
        require(msg.sender == owner, "MockDAO: Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnerTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MockDAO: zero owner");
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "MockDAO: zero treasury");
        treasury = Treasury(_treasury);
        emit TreasurySet(_treasury);
    }

    // --- DAO-only helpers ---

    function withdrawFromTreasury(address token, address recipient, uint256 amount) external onlyOwner {
        // This call will succeed only if this MockDAO holds the DAO role/admin in Treasury
        treasury.withdraw(token, recipient, amount);
        emit DaoWithdraw(token, recipient, amount, msg.sender);
    }

    function updateRelay(address oldRelay, address newRelay) external onlyOwner {
        treasury.updateRelay(oldRelay, newRelay);
        emit DaoRelayUpdate(oldRelay, newRelay, msg.sender);
    }
}
