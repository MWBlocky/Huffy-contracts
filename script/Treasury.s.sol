// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Treasury} from "../src/Treasury.sol";

contract DeployTreasury is Script {
    function run() external {
        address htkToken = vm.envAddress("HTK_TOKEN_ADDRESS");
        address saucerswapRouter = vm.envAddress("SAUCERSWAP_ROUTER");
        address daoAdmin = vm.envOr("DAO_ADMIN_ADDRESS", msg.sender);
        address relay = vm.envOr("RELAY_ADDRESS", msg.sender);

        require(htkToken != address(0), "HTK_TOKEN_ADDRESS not set");
        require(saucerswapRouter != address(0), "SAUCERSWAP_ROUTER not set");
        require(daoAdmin != address(0), "DAO_ADMIN_ADDRESS not set");
        require(relay != address(0), "RELAY_ADDRESS not set");

        console.log("Deployer:", msg.sender);
        console.log("HTK Token:", htkToken);
        console.log("Saucerswap Router:", saucerswapRouter);
        console.log("DAO Admin:", daoAdmin);
        console.log("Relay:", relay);

        vm.startBroadcast();

        Treasury treasury = new Treasury(htkToken, saucerswapRouter, daoAdmin, relay);

        vm.stopBroadcast();

        console.log("Treasury deployed at:", address(treasury));
    }
}
