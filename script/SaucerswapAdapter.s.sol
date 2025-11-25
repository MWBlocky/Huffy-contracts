// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SaucerswapAdapter} from "../src/adapters/SaucerswapAdapter.sol";

contract DeploySaucerswapAdapter is Script {
    function run() external {
        address proxy = vm.envAddress("SWAP_ROUTER_PROXY_ADDRESS");

        console.log("Deployer:", msg.sender);
        console.log("Swap Router Proxy:", proxy);

        vm.startBroadcast();

        SaucerswapAdapter adapter = new SaucerswapAdapter(proxy);

        vm.stopBroadcast();

        console.log("SaucerswapAdapter deployed at:", address(adapter));
    }
}
