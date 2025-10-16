// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Treasury} from "../src/Treasury.sol";

contract DeployTreasury is Script {
    function run() external {
        // Load environment variables
        address htkToken = vm.envAddress("HTK_TOKEN_ADDRESS");
        address saucerswapRouter = vm.envOr(
            "SAUCERSWAP_ROUTER",
            address(0x00000000000000000000000000000000001A9B39) // Hedera Testnet Saucerswap Router
        );
        address daoAdmin = vm.envOr("DAO_ADMIN_ADDRESS", msg.sender);
        address relay = vm.envOr("RELAY_ADDRESS", msg.sender);

        console.log("=== Deploying Treasury to Hedera Testnet ===");
        console.log("Deployer:", msg.sender);
        console.log("HTK Token:", htkToken);
        console.log("Saucerswap Router:", saucerswapRouter);
        console.log("DAO Admin:", daoAdmin);
        console.log("Relay:", relay);

        require(htkToken != address(0), "HTK_TOKEN_ADDRESS not set");

        vm.startBroadcast();

        Treasury treasury = new Treasury(htkToken, saucerswapRouter, daoAdmin, relay);

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("Treasury deployed at:", address(treasury));
    }
}
