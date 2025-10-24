// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockDAO} from "../src/mocks/MockDAO.sol";
import {Treasury} from "../src/Treasury.sol";

contract MockDAOScript is Script {
    function run() external {
        vm.startBroadcast();

        MockDAO mockDao = new MockDAO();
        console.log("Mock DAO:", address(mockDao));

        address treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
        Treasury treasury = Treasury(treasuryAddress);

        treasury.grantRole(treasury.DEFAULT_ADMIN_ROLE(), address(mockDao));

        address relay = vm.envOr("RELAY_ADDRESS", msg.sender);

        mockDao.setTreasury(address(treasury));
        mockDao.updateRelay(msg.sender, relay);

        vm.stopBroadcast();
    }
}
