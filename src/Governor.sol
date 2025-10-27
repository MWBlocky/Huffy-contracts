// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {HuffyTimelock} from "./Timelock.sol";
import {Governor} from "../lib/openzeppelin-contracts/contracts/governance/Governor.sol";
import {SafeCast} from "../lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

contract HuffyGovernor is Governor {
    HuffyTimelock public timelock;
    uint256 public initialProposalId;

    constructor(string memory name_, HuffyTimelock timelock_) Governor(name_) {
        timelock = timelock_;

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(0);
        values[0] = 0;
        calldatas[0] = "";

        string memory description = "Initial test proposal";

        initialProposalId = propose(targets, values, calldatas, description);
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
        bytes32 salt = descriptionHash;
        uint256 delay = timelock.getMinDelay();
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), salt, delay);
        return SafeCast.toUint48(block.timestamp + delay);
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

    function _countVote(uint256, address, uint8, uint256, bytes memory) internal pure override returns (uint256) {
        return 1;
    }

    function COUNTING_MODE() public pure override returns (string memory) {
        return "support=bravo";
    }

    function hasVoted(uint256, address) external pure override returns (bool) {
        return true;
    }
}
