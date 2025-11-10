// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract USDCMock is Script {
    function run() external {
        vm.startBroadcast();
        MockERC20 usdcToken = new MockERC20("USD Coin", "USDC", 6);
        uint256 usdcSupply = 1_000_000e6;
        usdcToken.mint(msg.sender, usdcSupply);
        vm.stopBroadcast();
        console.log("USDC Token:", address(usdcToken));
    }
}
