// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Governor } from "../lib/openzeppelin-contracts/contracts/governance/Governor.sol";
import { TimelockController } from  "../lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

contract HuffyGovernor is Governor {
    TimelockController public timelock;

    constructor(string memory name_, TimelockController timelock_) Governor(name_) {
        timelock = timelock_;
    }

    function _executor() internal view override returns (address) {
        return address(timelock);
    }

    function _queueOperations(
        uint256,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override returns (uint48) {
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), descriptionHash, timelock.getMinDelay());
        return uint48(block.timestamp + timelock.getMinDelay());
    }

    function clock() public view override returns (uint48) {
        return uint48(block.number);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=blocknumber";
    }

    function votingDelay() public pure override returns (uint256) {
        return 1;
    }

    function votingPeriod() public pure override returns (uint256) {
        return 45818;
    }

    function quorum(uint256) public pure override returns (uint256) {
        return 0;
    }

    function _quorumReached(uint256) internal pure override returns (bool) {
        return true;
    }

    function _voteSucceeded(uint256) internal pure override returns (bool) {
        return true;
    }

    function _getVotes(address, uint256, bytes memory) internal pure override returns (uint256) {
        return 1;
    }

    function _countVote(
        uint256,
        address,
        uint8,
        uint256,
        bytes memory
    ) internal pure override returns (uint256) {
        return 1;
    }

    function COUNTING_MODE() public pure override returns (string memory) {
        return "support=bravo";
    }

    function hasVoted(uint256, address) external pure override returns (bool) {
        return false;
    }
}
