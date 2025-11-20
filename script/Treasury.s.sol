// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Treasury} from "../src/Treasury.sol";

contract DeployTreasury is Script {
    function run() external {
        address htkToken = vm.envAddress("HTK_TOKEN_ADDRESS");
        address swapAdapter = vm.envOr("SWAP_ADAPTER_ADDRESS", address(0));
        address daoAdmin = vm.envOr("DAO_ADMIN_ADDRESS", msg.sender);
        address relay = vm.envOr("RELAY_ADDRESS", msg.sender);

        require(htkToken != address(0), "HTK_TOKEN_ADDRESS not set");
        require(swapAdapter != address(0), "SWAP_ADAPTER_ADDRESS not set");
        require(daoAdmin != address(0), "DAO_ADMIN_ADDRESS not set");
        require(relay != address(0), "RELAY_ADDRESS not set");

        console.log("Deployer:", msg.sender);
        console.log("HTK Token:", htkToken);
        console.log("Swap Adapter:", swapAdapter);
        console.log("DAO Admin:", daoAdmin);
        console.log("Relay:", relay);

        vm.startBroadcast();

        Treasury treasury = new Treasury(htkToken, swapAdapter, daoAdmin, relay);

        vm.stopBroadcast();

        console.log("Treasury deployed at:", address(treasury));
    }
}
