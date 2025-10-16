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

        // Verify configuration
        console.log("\nVerifying deployment...");
        console.log("HTK Token (from contract):", treasury.HTK_TOKEN());
        console.log("Router (from contract):", address(treasury.SAUCERSWAP_ROUTER()));

        console.log("\n=== Next Steps ===");
        console.log("1. If relay is deployer, deploy Relay contract");
        console.log("2. Call treasury.updateRelay(oldRelay, newRelay) from DAO admin");
        console.log("3. Fund the treasury with tokens using deposit()");
        console.log("4. Verify contract on Hedera Explorer");

        // Save deployment info
        string memory deploymentInfo = string.concat(
            "{\n",
            '  "network": "hedera-testnet",\n',
            '  "timestamp": "',
            vm.toString(block.timestamp),
            '",\n',
            '  "deployer": "',
            vm.toString(msg.sender),
            '",\n',
            '  "treasury": "',
            vm.toString(address(treasury)),
            '",\n',
            '  "htkToken": "',
            vm.toString(htkToken),
            '",\n',
            '  "saucerswapRouter": "',
            vm.toString(saucerswapRouter),
            '",\n',
            '  "daoAdmin": "',
            vm.toString(daoAdmin),
            '",\n',
            '  "relay": "',
            vm.toString(relay),
            '"\n',
            "}"
        );

        vm.writeFile(string.concat("deployments/treasury-", vm.toString(block.timestamp), ".json"), deploymentInfo);

        console.log("\nDeployment info saved to deployments/ directory");
    }
}
