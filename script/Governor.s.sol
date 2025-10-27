// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {HuffyGovernor} from "../src/Governor.sol";
import {HuffyTimelock} from "../src/Timelock.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract DeployGovernor is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);

        proposers[0] = vm.addr(deployerPrivateKey);
        executors[0] = vm.addr(deployerPrivateKey);

        HuffyTimelock timelock = new HuffyTimelock(1, proposers, executors, msg.sender);
        HuffyGovernor governor = new HuffyGovernor("HuffyGovernor", timelock);

        console.log("HuffyTimelock deployed at:", address(timelock));
        console.log("HuffyGovernor deployed at:", address(governor));
        console.log("Initial proposal ID:", governor.initialProposalId());

        vm.stopBroadcast();
    }
}
