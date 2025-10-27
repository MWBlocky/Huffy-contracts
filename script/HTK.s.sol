// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HTK} from "../src/HTK.sol";

contract DeployHTK is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        uint256 initialSupply;
        try vm.envUint("INITIAL_SUPPLY") returns (uint256 v) {
            initialSupply = v;
        } catch {
            initialSupply = 10_000_000e18;
        }

        address initialOwner;
        try vm.envAddress("INITIAL_OWNER") returns (address a) {
            initialOwner = a;
        } catch {
            initialOwner = msg.sender;
        }

        HTK htk = new HTK(initialOwner, initialSupply);

        console.log("HTK deployed at:", address(htk));
        console.log("Initial owner:", initialOwner);
        console.log("Initial supply:", initialSupply);

        vm.stopBroadcast();
    }
}
