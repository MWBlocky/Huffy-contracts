// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PairWhitelist} from "../src/PairWhitelist.sol";

contract DeployPairWhitelist is Script {
    function run() external {
        address daoAdmin = vm.envOr("DAO_ADMIN_ADDRESS", msg.sender);

        console.log("Deployer:", msg.sender);
        console.log("DAO Admin:", daoAdmin);

        vm.startBroadcast();

        PairWhitelist pairWhitelist = new PairWhitelist(daoAdmin);

        vm.stopBroadcast();

        console.log("PairWhitelist deployed at:", address(pairWhitelist));
    }
}
