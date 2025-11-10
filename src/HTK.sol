// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "../lib/openzeppelin-contracts/contracts/utils/Nonces.sol";

/**
 * @title Huffy Governance Token (HTK)
 * @notice Standard ERC20 compatible on EVM (incl. Hedera EVM)
 * ERC20Permit (EIP-2612)
 * ERC20Votes for on-chain governance (delegation, vote checkpoints, snapshots)
 */
contract HTK is ERC20, ERC20Permit, ERC20Votes {
    /// @param initialOwner Address that will receive the initial supply
    /// @param initialSupply Amount minted on deploy (18 decimals)
    constructor(address initialOwner, uint256 initialSupply)
        ERC20("Huffy Governance Token", "HTK")
        ERC20Permit("Huffy Governance Token")
    {
        require(initialOwner != address(0), "HTK: owner=0");
        _mint(initialOwner, initialSupply);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
