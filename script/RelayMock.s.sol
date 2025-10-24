// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockRelay} from "../src/mocks/MockRelay.sol";

contract RelayMock is Script {
    function run() external {
        address treasury = 0x0000000000000000000000000000000000000000;
        vm.startBroadcast();
        MockRelay mockRelay = new MockRelay(treasury);
        vm.stopBroadcast();
        console.log("Mock Relay:", address(mockRelay));
    }
}
