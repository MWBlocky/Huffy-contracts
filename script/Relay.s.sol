// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Relay} from "../src/Relay.sol";

contract DeployRelay is Script {
    function run() external {
        address pairWhitelist = vm.envAddress("PAIR_WHITELIST_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address saucerswapRouter = vm.envAddress("SAUCERSWAP_ROUTER");
        address daoAdmin = vm.envOr("DAO_ADMIN_ADDRESS", msg.sender);

        // Parse initial traders (comma-separated addresses)
        address[] memory initialTraders;
        try vm.envString("INITIAL_TRADERS") returns (string memory tradersEnv) {
            if (bytes(tradersEnv).length > 0) {
                initialTraders = _parseAddresses(tradersEnv);
            }
        } catch {
            // If env var not set, use deployer as default
            initialTraders = new address[](1);
            initialTraders[0] = msg.sender;
        }

        // If parsing resulted in empty array, use deployer as default
        if (initialTraders.length == 0) {
            initialTraders = new address[](1);
            initialTraders[0] = msg.sender;
        }

        // Risk parameters (with defaults)
        uint256 maxTradeBps;
        uint256 maxSlippageBps;
        uint256 tradeCooldownSec;

        try vm.envUint("MAX_TRADE_BPS") returns (uint256 value) {
            maxTradeBps = value;
        } catch {
            maxTradeBps = 1000; // Default: 10%
        }

        try vm.envUint("MAX_SLIPPAGE_BPS") returns (uint256 value) {
            maxSlippageBps = value;
        } catch {
            maxSlippageBps = 500; // Default: 5%
        }

        try vm.envUint("TRADE_COOLDOWN_SEC") returns (uint256 value) {
            tradeCooldownSec = value;
        } catch {
            tradeCooldownSec = 3600; // Default: 1 hour
        }

        console.log("Deployer:", msg.sender);
        console.log("PairWhitelist:", pairWhitelist);
        console.log("Treasury:", treasury);
        console.log("Saucerswap Router:", saucerswapRouter);
        console.log("DAO Admin:", daoAdmin);
        console.log("Initial Traders Count:", initialTraders.length);
        for (uint256 i = 0; i < initialTraders.length; i++) {
            console.log("  Trader", i, ":", initialTraders[i]);
        }
        console.log("Max Trade BPS:", maxTradeBps);
        console.log("Max Slippage BPS:", maxSlippageBps);
        console.log("Trade Cooldown (sec):", tradeCooldownSec);

        require(pairWhitelist != address(0), "PAIR_WHITELIST_ADDRESS not set");
        require(treasury != address(0), "TREASURY_ADDRESS not set");

        vm.startBroadcast();

        Relay relay = new Relay(
            pairWhitelist,
            treasury,
            saucerswapRouter,
            daoAdmin,
            initialTraders,
            maxTradeBps,
            maxSlippageBps,
            tradeCooldownSec
        );

        vm.stopBroadcast();

        console.log("Relay deployed at:", address(relay));
    }

    /**
     * @notice Parse comma-separated addresses from string
     * @param addresses String containing comma-separated addresses
     * @return Array of parsed addresses
     */
    function _parseAddresses(string memory addresses) private pure returns (address[] memory) {
        if (bytes(addresses).length == 0) {
            return new address[](0);
        }

        // Count commas to determine array size
        uint256 count = 1;
        bytes memory addrBytes = bytes(addresses);
        for (uint256 i = 0; i < addrBytes.length; i++) {
            if (addrBytes[i] == ",") {
                count++;
            }
        }

        address[] memory result = new address[](count);
        uint256 index = 0;
        uint256 start = 0;

        for (uint256 i = 0; i <= addrBytes.length; i++) {
            if (i == addrBytes.length || addrBytes[i] == ",") {
                // Extract substring
                bytes memory addrStr = new bytes(i - start);
                for (uint256 j = 0; j < i - start; j++) {
                    addrStr[j] = addrBytes[start + j];
                }

                // Convert to address (simplified - assumes valid hex string)
                result[index] = _parseAddress(string(addrStr));
                index++;
                start = i + 1;
            }
        }

        return result;
    }

    /**
     * @notice Parse single address from string (simplified)
     * @param addr String representation of address
     * @return Parsed address
     */
    function _parseAddress(string memory addr) private pure returns (address) {
        bytes memory addrBytes = bytes(addr);
        require(addrBytes.length == 42, "Invalid address length");
        require(addrBytes[0] == "0" && addrBytes[1] == "x", "Invalid address prefix");

        uint160 result = 0;
        for (uint256 i = 2; i < 42; i++) {
            result *= 16;
            uint8 digit = uint8(addrBytes[i]);

            if (digit >= 48 && digit <= 57) {
                result += digit - 48; // 0-9
            } else if (digit >= 65 && digit <= 70) {
                result += digit - 55; // A-F
            } else if (digit >= 97 && digit <= 102) {
                result += digit - 87; // a-f
            } else {
                revert("Invalid address character");
            }
        }

        return address(result);
    }
}
