// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract HTKMock is Script {
    function run() external {
        vm.startBroadcast();
        MockERC20 htkToken = new MockERC20("HTK Governance Token", "HTK", 18);
        uint256 initialSupply = 10_000_000e18;
        htkToken.mint(msg.sender, initialSupply);
        vm.stopBroadcast();
        console.log("HTK Token:", address(htkToken));
    }
}
