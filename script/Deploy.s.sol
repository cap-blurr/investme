// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Vault} from "../src/Vault.sol";
import {AIWalletController} from "../src/AIWalletController.sol";
import {FeeCollector} from "../src/FeeCollector.sol";
import {EmergencyModule} from "../src/EmergencyModule.sol";
import {UniswapV3Adapter} from "../src/UniswapV3Adapter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAutoYield is Script {
    // Configuration
    struct DeployConfig {
        address owner;
        address aiWallet;
        address feeRecipient;
        address[] multiSigSigners;
        uint256 requiredConfirmations;
        address usdc;
        address[] initialWhitelistedDexes;
        address[] initialApprovedTokens;
    }

    function run() external {
        // Load configuration based on chain
        DeployConfig memory config = getConfig();
        
        // Start broadcast
        vm.startBroadcast();

        // 1. Deploy Vault (UUPS Upgradeable)
        Vault vaultImpl = new Vault();
        bytes memory initData = abi.encodeCall(Vault.initialize, (config.usdc, config.owner));
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), initData);
        Vault vault = Vault(address(vaultProxy));
        console2.log("Vault deployed at:", address(vault));

        // 2. Deploy AIWalletController
        AIWalletController controller = new AIWalletController(address(vault), config.aiWallet);
        console2.log("AIWalletController deployed at:", address(controller));

        // 3. Deploy FeeCollector
        FeeCollector feeCollector = new FeeCollector(address(vault), config.feeRecipient);
        console2.log("FeeCollector deployed at:", address(feeCollector));

        // 4. Deploy EmergencyModule
        EmergencyModule emergency = new EmergencyModule(
            address(vault),
            address(controller),
            config.multiSigSigners,
            config.requiredConfirmations
        );
        console2.log("EmergencyModule deployed at:", address(emergency));

        // 5. Deploy DEX Adapters
        UniswapV3Adapter uniswapAdapter = new UniswapV3Adapter();
        console2.log("UniswapV3Adapter deployed at:", address(uniswapAdapter));

        // 6. Configure AIWalletController
        // Whitelist DEXes
        for (uint256 i = 0; i < config.initialWhitelistedDexes.length; i++) {
            controller.whitelistDex(config.initialWhitelistedDexes[i]);
        }
        controller.whitelistDex(address(uniswapAdapter)); // Add our adapter

        // Approve tokens
        for (uint256 i = 0; i < config.initialApprovedTokens.length; i++) {
            controller.approveToken(config.initialApprovedTokens[i]);
        }

        // Set initial limits
        controller.setLimits(
            100,          // 1% max slippage
            1_000_000e6,  // 1M USDC max position
            100           // 100 operations per day
        );

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Vault:", address(vault));
        console2.log("AIWalletController:", address(controller));
        console2.log("FeeCollector:", address(feeCollector));
        console2.log("EmergencyModule:", address(emergency));
        console2.log("UniswapV3Adapter:", address(uniswapAdapter));
        console2.log("========================\n");

        // Save deployment addresses
        saveDeployment(
            address(vault),
            address(controller),
            address(feeCollector),
            address(emergency),
            address(uniswapAdapter)
        );
    }

    function getConfig() internal view returns (DeployConfig memory) {
        uint256 chainId = block.chainid;

        // Mainnet configuration
        if (chainId == 1) {
            address[] memory multiSig = new address[](3);
            multiSig[0] = 0x1111111111111111111111111111111111111111; // Replace with real addresses
            multiSig[1] = 0x2222222222222222222222222222222222222222;
            multiSig[2] = 0x3333333333333333333333333333333333333333;

            address[] memory dexes = new address[](1);
            dexes[0] = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // Uniswap V3 SwapRouter

            address[] memory tokens = new address[](2);
            tokens[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
            tokens[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH

            return DeployConfig({
                owner: msg.sender,
                aiWallet: 0x4444444444444444444444444444444444444444, // Replace with AI wallet
                feeRecipient: 0x5555555555555555555555555555555555555555, // Replace
                multiSigSigners: multiSig,
                requiredConfirmations: 2,
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                initialWhitelistedDexes: dexes,
                initialApprovedTokens: tokens
            });
        }
        // Base Mainnet
        else if (chainId == 8453) {
            address[] memory multiSig = new address[](3);
            multiSig[0] = msg.sender; // For testing

            address[] memory dexes = new address[](1);
            dexes[0] = 0x2626664c2603336E57B271c5C0b26F421741e481; // Uniswap V3 on Base

            address[] memory tokens = new address[](2);
            tokens[0] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on Base
            tokens[1] = 0x4200000000000000000000000000000000000006; // WETH on Base

            return DeployConfig({
                owner: msg.sender,
                aiWallet: msg.sender, // For testing
                feeRecipient: msg.sender,
                multiSigSigners: multiSig,
                requiredConfirmations: 1,
                usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                initialWhitelistedDexes: dexes,
                initialApprovedTokens: tokens
            });
        }
        // Testnet / Local
        else {
            address[] memory multiSig = new address[](1);
            multiSig[0] = msg.sender;

            address[] memory dexes = new address[](0);
            address[] memory tokens = new address[](1);
            tokens[0] = address(0); // Will need to deploy mock USDC

            return DeployConfig({
                owner: msg.sender,
                aiWallet: msg.sender,
                feeRecipient: msg.sender,
                multiSigSigners: multiSig,
                requiredConfirmations: 1,
                usdc: address(0), // Deploy mock in test
                initialWhitelistedDexes: dexes,
                initialApprovedTokens: tokens
            });
        }
    }

    function saveDeployment(
        address vault,
        address controller,
        address feeCollector,
        address emergency,
        address uniswapAdapter
    ) internal {
        string memory json = "deployment";
        vm.serializeAddress(json, "vault", vault);
        vm.serializeAddress(json, "controller", controller);
        vm.serializeAddress(json, "feeCollector", feeCollector);
        vm.serializeAddress(json, "emergency", emergency);
        string memory output = vm.serializeAddress(json, "uniswapAdapter", uniswapAdapter);
        
        string memory filename = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(output, filename);
    }
}