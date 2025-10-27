// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {HuffyGovernor} from "../src/Governor.sol";
import {HuffyTimelock} from "../src/Timelock.sol";
import {HTK} from "../src/HTK.sol";
import {IVotes} from "../lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol";
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

        // Deploy a fresh HTK (ERC20Votes) for testing/demo. In production, pass an existing token address.
        uint256 initialSupply = 10_000_000e18;
        HTK htk = new HTK(msg.sender, initialSupply);
        IVotes votesToken = IVotes(address(htk));

        // Governor parameters (example values)
        uint256 votingDelay = 1; // blocks
        uint256 votingPeriod = 45818; // ~1 week @13s blocks
        uint256 proposalThreshold = 0; // no threshold
        uint256 quorumNumerator = 4; // 4%

        HuffyGovernor governor = new HuffyGovernor(
            "HuffyGovernor", votesToken, timelock, votingDelay, votingPeriod, proposalThreshold, quorumNumerator
        );

        console.log("HuffyTimelock deployed at:", address(timelock));
        console.log("HTK deployed at:", address(htk));
        console.log("HuffyGovernor deployed at:", address(governor));
        console.log("proposalThreshold:", governor.proposalThreshold());
        console.log("votingDelay:", governor.votingDelay());
        console.log("votingPeriod:", governor.votingPeriod());

        vm.stopBroadcast();
    }
}
