// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {OptimizedVault} from "../src/Vault.sol";
import {OptimizedAIWalletController} from "../src/AIWalletController.sol";
import {OptimizedFeeCollector} from "../src/FeeCollector.sol";
import {OptimizedEmergencyModule} from "../src/EmergencyModule.sol";
import {UniswapV3Adapter} from "../src/UniswapV3Adapter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAutoYield is Script {
    // Configuration
    struct DeployConfig {
        address owner;
        address aiWallet;
        address feeRecipient;
        address[] multiSigSigners;
        uint32 requiredConfirmations;
        address usdc;
        address[] initialWhitelistedDexes;
        address[] initialApprovedTokens;
    }

    function run() external {
        // Load configuration based on chain
        DeployConfig memory config = getConfig();
        
        console2.log("Deploying with configuration:");
        console2.log("Owner:", config.owner);
        console2.log("AI Wallet:", config.aiWallet);
        console2.log("Fee Recipient:", config.feeRecipient);
        
        // Start broadcast - Foundry will use the account specified
        vm.startBroadcast();

        // 1. Deploy Vault (UUPS Upgradeable)
        OptimizedVault vaultImpl = new OptimizedVault();
        // Initialize with the config owner, not msg.sender
        bytes memory initData = abi.encodeCall(OptimizedVault.initialize, (config.usdc, config.owner));
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), initData);
        OptimizedVault vault = OptimizedVault(address(vaultProxy));
        console2.log("Vault deployed at:", address(vault));

        // 2. Deploy AIWalletController
        OptimizedAIWalletController controller = new OptimizedAIWalletController(address(vault), config.aiWallet);
        console2.log("AIWalletController deployed at:", address(controller));

        // 3. Deploy FeeCollector
        OptimizedFeeCollector feeCollector = new OptimizedFeeCollector(address(vault), config.feeRecipient);
        console2.log("FeeCollector deployed at:", address(feeCollector));

        // 4. Deploy EmergencyModule
        OptimizedEmergencyModule emergency = new OptimizedEmergencyModule(
            address(vault),
            address(controller),
            config.multiSigSigners,
            config.requiredConfirmations
        );
        console2.log("EmergencyModule deployed at:", address(emergency));

        // 5. Deploy DEX Adapters
        UniswapV3Adapter uniswapAdapter = new UniswapV3Adapter();
        console2.log("UniswapV3Adapter deployed at:", address(uniswapAdapter));

        // 6. Configure Vault (now this will work because deployer is the owner)
        vault.setAIController(address(controller));
        vault.setFeeCollector(address(feeCollector));

        // 7. Configure AIWalletController
        // Set emergency module
        controller.setEmergencyModule(address(emergency));
        
        // Prepare arrays for batch operations
        address[] memory dexesToWhitelist = new address[](config.initialWhitelistedDexes.length + 1);
        bool[] memory dexStatuses = new bool[](dexesToWhitelist.length);
        
        for (uint256 i = 0; i < config.initialWhitelistedDexes.length; i++) {
            dexesToWhitelist[i] = config.initialWhitelistedDexes[i];
            dexStatuses[i] = true;
        }
        dexesToWhitelist[dexesToWhitelist.length - 1] = address(uniswapAdapter);
        dexStatuses[dexStatuses.length - 1] = true;
        
        controller.batchWhitelistDex(dexesToWhitelist, dexStatuses);

        // Approve tokens
        bool[] memory tokenStatuses = new bool[](config.initialApprovedTokens.length);
        for (uint256 i = 0; i < tokenStatuses.length; i++) {
            tokenStatuses[i] = true;
        }
        controller.batchApproveTokens(config.initialApprovedTokens, tokenStatuses);

        // Set initial limits
        controller.setLimits(
            100,          // 1% max slippage
            1_000_000e6,  // 1M USDC max position
            100           // 100 operations per day
        );

        // 8. Transfer ownership to multi-sig (if specified and different from config.owner)
        // Note: In this setup, config.owner is already the owner, so no transfer needed
        
        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Vault:", address(vault));
        console2.log("AIWalletController:", address(controller));
        console2.log("FeeCollector:", address(feeCollector));
        console2.log("EmergencyModule:", address(emergency));
        console2.log("UniswapV3Adapter:", address(uniswapAdapter));
        console2.log("Owner:", config.owner);
        console2.log("========================\n");

        // Save deployment addresses
        saveDeployment(
            address(vault),
            address(controller),
            address(feeCollector),
            address(emergency),
            address(uniswapAdapter),
            config.owner
        );
    }

    function getConfig() internal view returns (DeployConfig memory) {
        uint256 chainId = block.chainid;

        // Mainnet configuration
        if (chainId == 1) {
            address deployerAddress = 0xdB487A73A5b7EF3e773ec115F8C209C12E4EBA37; // Your wallet
            
            address[] memory multiSig = new address[](3);
            multiSig[0] = deployerAddress; // Include deployer in multisig
            multiSig[1] = 0x2222222222222222222222222222222222222222; // Replace with real address
            multiSig[2] = 0x3333333333333333333333333333333333333333; // Replace with real address

            address[] memory dexes = new address[](1);
            dexes[0] = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // Uniswap V3 SwapRouter

            address[] memory tokens = new address[](2);
            tokens[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
            tokens[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH

            return DeployConfig({
                owner: deployerAddress,
                aiWallet: deployerAddress, // Replace with actual AI wallet when ready
                feeRecipient: deployerAddress, // Replace with actual fee recipient
                multiSigSigners: multiSig,
                requiredConfirmations: 2,
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                initialWhitelistedDexes: dexes,
                initialApprovedTokens: tokens
            });
        }
        // Base Mainnet
        else if (chainId == 8453) {
            address deployerAddress = 0xdB487A73A5b7EF3e773ec115F8C209C12E4EBA37; // Your actual wallet
            
            address[] memory multiSig = new address[](1);
            multiSig[0] = deployerAddress;

            address[] memory dexes = new address[](1);
            dexes[0] = 0x2626664c2603336E57B271c5C0b26F421741e481; // Uniswap V3 on Base

            address[] memory tokens = new address[](2);
            tokens[0] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on Base
            tokens[1] = 0x4200000000000000000000000000000000000006; // WETH on Base

            return DeployConfig({
                owner: deployerAddress,
                aiWallet: deployerAddress, // For testing
                feeRecipient: deployerAddress, // For testing
                multiSigSigners: multiSig,
                requiredConfirmations: 1,
                usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                initialWhitelistedDexes: dexes,
                initialApprovedTokens: tokens
            });
        }
        // Testnet / Local
        else {
            address deployerAddress = 0xdB487A73A5b7EF3e773ec115F8C209C12E4EBA37; // Your wallet
            
            address[] memory multiSig = new address[](1);
            multiSig[0] = deployerAddress;

            address[] memory dexes = new address[](0);
            address[] memory tokens = new address[](1);
            tokens[0] = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F; // USDC Goerli

            return DeployConfig({
                owner: deployerAddress,
                aiWallet: deployerAddress,
                feeRecipient: deployerAddress,
                multiSigSigners: multiSig,
                requiredConfirmations: 1,
                usdc: tokens[0],
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
        address uniswapAdapter,
        address deployer
    ) internal {
        string memory json = "deployment";
        vm.serializeAddress(json, "vault", vault);
        vm.serializeAddress(json, "controller", controller);
        vm.serializeAddress(json, "feeCollector", feeCollector);
        vm.serializeAddress(json, "emergency", emergency);
        vm.serializeAddress(json, "uniswapAdapter", uniswapAdapter);
        string memory output = vm.serializeAddress(json, "deployer", deployer);
        
        string memory filename = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(output, filename);
    }
}