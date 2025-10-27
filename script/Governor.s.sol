// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {HuffyGovernor} from "../src/Governor.sol";
import {HuffyTimelock} from "../src/Timelock.sol";
import {PairWhitelist} from "../src/PairWhitelist.sol";
import {ParameterStore} from "../src/ParameterStore.sol";
import {IVotes} from "../lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract DeployGovernor is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Timelock delay: read from env TIMELOCK_DELAY (seconds), default to 2 days if not provided
        uint256 minDelay;
        try vm.envUint("TIMELOCK_DELAY") returns (uint256 v) {
            minDelay = v;
        } catch {
            minDelay = 2 days;
        }

        // Set constructor arrays: no proposers initially, open executor to anyone via address(0)
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        // Deploy Timelock with deployer as temporary admin
        HuffyTimelock timelock = new HuffyTimelock(minDelay, proposers, executors, msg.sender);

        address htk = vm.envAddress("HTK_TOKEN_ADDRESS");
        IVotes votesToken = IVotes(htk);

        // Governor parameters (example values)
        uint256 votingDelay = 1; // blocks
        uint256 votingPeriod = 45818; // ~1 week @13s blocks
        uint256 proposalThreshold = 0; // no threshold
        uint256 quorumNumerator = 4; // 4%

        HuffyGovernor governor = new HuffyGovernor(
            "HuffyGovernor", votesToken, timelock, votingDelay, votingPeriod, proposalThreshold, quorumNumerator
        );

        // Configure roles on the Timelock
        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        bytes32 DEFAULT_ADMIN_ROLE = timelock.DEFAULT_ADMIN_ROLE();

        // Governor proposes and cancels; anyone can execute via address(0)
        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(CANCELLER_ROLE, address(governor));
        // address(0) executor already set by constructor, but grant explicitly for clarity
        timelock.grantRole(EXECUTOR_ROLE, address(0));

        // Make timelock self-admin and remove deployer control
        timelock.grantRole(DEFAULT_ADMIN_ROLE, address(timelock));
        timelock.revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // Ensure deployer has no special proposer/executor privileges
        timelock.revokeRole(PROPOSER_ROLE, msg.sender);
        timelock.revokeRole(EXECUTOR_ROLE, msg.sender);

        // Deploy DAO-controlled modules owned by Timelock
        PairWhitelist pairWhitelist = new PairWhitelist(address(timelock));
        // Example initial parameters
        ParameterStore parameterStore = new ParameterStore(address(timelock), 1_000, 300, 3600);

        console.log("HuffyTimelock deployed at:", address(timelock));
        console.log("HTK deployed at:", address(htk));
        console.log("HuffyGovernor deployed at:", address(governor));
        console.log("PairWhitelist deployed at:", address(pairWhitelist));
        console.log("ParameterStore deployed at:", address(parameterStore));
        console.log("Timelock delay (sec):", minDelay);
        console.log("proposalThreshold:", governor.proposalThreshold());
        console.log("votingDelay:", governor.votingDelay());
        console.log("votingPeriod:", governor.votingPeriod());

        vm.stopBroadcast();
    }
}
