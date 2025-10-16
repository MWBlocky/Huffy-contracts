// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockSaucerswapRouter} from "../src/mocks/MockSaucerswapRouter.sol";
import {MockRelay} from "../src/mocks/MockRelay.sol";
import {SafeERC20, IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract DeployMocks is Script {
    using SafeERC20 for IERC20;

    function run() external {
        console.log("=== Deploying Mock Contracts for Testing ===");
        console.log("Deployer:", msg.sender);

        vm.startBroadcast();

        // 1. Deploy Mock HTK Token
        console.log("\n1. Deploying Mock HTK Token...");
        MockERC20 htkToken = new MockERC20("HTK Governance Token", "HTK", 18);
        console.log("HTK Token:", address(htkToken));

        // Mint initial supply
        uint256 initialSupply = 10_000_000e18; // 10M HTK
        htkToken.mint(msg.sender, initialSupply);
        console.log("Minted", initialSupply / 1e18, "HTK to deployer");

        // 2. Deploy Mock USDC Token
        console.log("\n2. Deploying Mock USDC Token...");
        MockERC20 usdcToken = new MockERC20("USD Coin", "USDC", 6);
        console.log("USDC Token:", address(usdcToken));

        // Mint USDC
        uint256 usdcSupply = 1_000_000e6; // 1M USDC
        usdcToken.mint(msg.sender, usdcSupply);
        console.log("Minted", usdcSupply / 1e6, "USDC to deployer");

        // 3. Deploy Mock Saucerswap Router
        console.log("\n3. Deploying Mock Saucerswap Router...");
        MockSaucerswapRouter router = new MockSaucerswapRouter();
        console.log("Saucerswap Router:", address(router));

        // Fund router with HTK
        uint256 routerHtkSupply = 5_000_000e18; // 5M HTK
        htkToken.mint(address(router), routerHtkSupply);
        console.log("Funded router with", routerHtkSupply / 1e18, "HTK");

        // Set exchange rate (1 USDC = 2 HTK)
        uint256 exchangeRate = 2e18;
        router.setExchangeRate(address(usdcToken), address(htkToken), exchangeRate);
        console.log("Set exchange rate: 1 USDC = 2 HTK");

        // 4. Deploy Treasury
        console.log("\n4. Deploying Treasury...");
        Treasury treasury = new Treasury(
            address(htkToken),
            address(router),
            msg.sender, // DAO admin
            msg.sender // Temporary relay
        );
        console.log("Treasury:", address(treasury));

        // Fund treasury with USDC
        uint256 treasuryUsdc = 100_000e6; // 100k USDC
        IERC20(address(usdcToken)).safeTransfer(address(treasury), treasuryUsdc);
        console.log("Funded treasury with", treasuryUsdc / 1e6, "USDC");

        // 5. Deploy Mock Relay
        console.log("\n5. Deploying Mock Relay...");
        MockRelay mockRelay = new MockRelay(address(treasury));
        console.log("Mock Relay:", address(mockRelay));

        // Update relay in treasury
        console.log("\n6. Updating Relay in Treasury...");
        treasury.updateRelay(msg.sender, address(mockRelay));
        console.log("Relay updated in Treasury");

        vm.stopBroadcast();

        // Summary
        console.log("\n=== Deployment Summary ===");
        console.log("HTK Token:", address(htkToken));
        console.log("USDC Token:", address(usdcToken));
        console.log("Saucerswap Router:", address(router));
        console.log("Treasury:", address(treasury));
        console.log("Mock Relay:", address(mockRelay));

        // Save deployment info
        _saveDeploymentInfo(
            address(htkToken),
            address(usdcToken),
            address(router),
            address(treasury),
            address(mockRelay),
            treasuryUsdc,
            routerHtkSupply
        );

        console.log("\nMock deployment complete! Ready for testing.");
    }

    function _saveDeploymentInfo(
        address htk,
        address usdc,
        address routerAddr,
        address treasuryAddr,
        address relayAddr,
        uint256 treasuryUsdcAmount,
        uint256 routerHtkAmount
    ) internal {
        string memory deploymentInfo = string.concat(
            "{\n",
            '  "network": "',
            vm.toString(block.chainid),
            '",\n',
            '  "timestamp": "',
            vm.toString(block.timestamp),
            '",\n',
            '  "deployer": "',
            vm.toString(msg.sender),
            '",\n',
            '  "htkToken": "',
            vm.toString(htk),
            '",\n',
            '  "usdcToken": "',
            vm.toString(usdc),
            '",\n',
            '  "saucerswapRouter": "',
            vm.toString(routerAddr),
            '",\n',
            '  "treasury": "',
            vm.toString(treasuryAddr),
            '",\n',
            '  "mockRelay": "',
            vm.toString(relayAddr),
            '",\n',
            '  "exchangeRate": "2.0",\n',
            '  "treasuryUSDC": "',
            vm.toString(treasuryUsdcAmount / 1e6),
            '",\n',
            '  "routerHTK": "',
            vm.toString(routerHtkAmount / 1e18),
            '"\n',
            "}"
        );

        vm.writeFile(string.concat("deployments/mocks-", vm.toString(block.timestamp), ".json"), deploymentInfo);

        console.log("\nDeployment info saved to deployments/ directory");
    }
}
