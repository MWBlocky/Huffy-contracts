// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SwapRouterProxyHedera} from "../src/SwapRouterProxyHedera.sol";

contract DeploySwapRouterProxyHedera is Script {
    function run() external {
        address router = vm.envAddress("SWAP_ROUTER_ADDRESS");
        address whbar = vm.envAddress("WHBAR_ADDRESS");

        vm.startBroadcast();

        SwapRouterProxyHedera proxy = new SwapRouterProxyHedera(router, whbar);

        vm.stopBroadcast();

        console.log("------------------------------------");
        console.log("SwapRouterProxyHedera deployed at:", address(proxy));
        console.log("------------------------------------");
    }
}
