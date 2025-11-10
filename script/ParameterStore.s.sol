// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ParameterStore} from "../src/ParameterStore.sol";

contract ParameterStoreDeploy is Script {
    function run() external returns (ParameterStore store) {
        address daoAdmin = vm.envOr("DAO_ADMIN_ADDRESS", msg.sender);

        vm.startBroadcast();
        store = new ParameterStore(daoAdmin, 1, 2, 3);
        vm.stopBroadcast();

        console.log("ParameterStore deployed at", address(store));

        return store;
    }
}
