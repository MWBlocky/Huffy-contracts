// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {HuffyTimelock} from "./Timelock.sol";
import {Governor} from "../lib/openzeppelin-contracts/contracts/governance/Governor.sol";
import {GovernorSettings} from "../lib/openzeppelin-contracts/contracts/governance/extensions/GovernorSettings.sol";
import {
    GovernorCountingSimple
} from "../lib/openzeppelin-contracts/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "../lib/openzeppelin-contracts/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "../lib/openzeppelin-contracts/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {
    GovernorTimelockControl
} from "../lib/openzeppelin-contracts/contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "../lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol";
import {SafeCast} from "../lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/**
 * @title Huffy Governor
 * @notice Governor contract using:
 * - GovernorSettings: voting delay/period, proposal threshold
 * - GovernorCountingSimple: support for Against/For/Abstain
 * - GovernorVotes: ERC20Votes token (HTK)
 * - GovernorVotesQuorumFraction: quorum as a fraction of total supply
 * - GovernorTimelockControl: queued execution via timelock
 */
contract HuffyGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /// @param name_ Governor name (for EIP-712 domain)
    /// @param token ERC20Votes-compatible token used for voting (HTK)
    /// @param timelock_ Timelock controller for queued execution
    /// @param votingDelay_ Delay (in blocks) before voting starts after proposal is created
    /// @param votingPeriod_ Duration (in blocks) of the voting period
    /// @param proposalThreshold_ Minimum number of votes required to create a proposal
    /// @param quorumNumerator_ Quorum numerator for GovernorVotesQuorumFraction (denominator = 100)
    constructor(
        string memory name_,
        IVotes token,
        HuffyTimelock timelock_,
        uint256 votingDelay_,
        uint256 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumNumerator_
    )
        Governor(name_)
        GovernorSettings(SafeCast.toUint48(votingDelay_), SafeCast.toUint32(votingPeriod_), proposalThreshold_)
        GovernorVotes(token)
        GovernorVotesQuorumFraction(quorumNumerator_)
        GovernorTimelockControl(timelock_)
    {}

    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId) public view override(Governor) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
