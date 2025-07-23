// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OptimizedVault} from "../src/Vault.sol";
import {OptimizedAIWalletController} from "../src/AIWalletController.sol";
import {OptimizedFeeCollector} from "../src/FeeCollector.sol";
import {OptimizedEmergencyModule} from "../src/EmergencyModule.sol";
import {UniswapV3Adapter} from "../src/UniswapV3Adapter.sol";

// Mock USDC for testing
contract MockUSDC is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }
    
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
}

contract AutoYieldTest is Test {
    // Contracts
    OptimizedVault public vault;
    OptimizedAIWalletController public controller;
    OptimizedFeeCollector public feeCollector;
    OptimizedEmergencyModule public emergency;
    UniswapV3Adapter public uniswapAdapter;
    MockUSDC public usdc;
    
    // Test accounts
    address public owner = address(0x1);
    address public aiWallet = address(0x2);
    address public feeRecipient = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);
    address[] public multiSigSigners;
    
    // Constants
    uint256 constant INITIAL_BALANCE = 1_000_000e6; // 1M USDC
    
    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();
        
        // Setup multi-sig signers
        multiSigSigners.push(address(0x10));
        multiSigSigners.push(address(0x11));
        multiSigSigners.push(address(0x12));
        
        // Deploy contracts
        vm.startPrank(owner);
        
        // Deploy vault (upgradeable)
        OptimizedVault vaultImpl = new OptimizedVault();
        bytes memory initData = abi.encodeCall(OptimizedVault.initialize, (address(usdc), owner));
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), initData);
        vault = OptimizedVault(address(vaultProxy));
        
        // Deploy other contracts
        controller = new OptimizedAIWalletController(address(vault), aiWallet);
        feeCollector = new OptimizedFeeCollector(address(vault), feeRecipient);
        emergency = new OptimizedEmergencyModule(
            address(vault),
            address(controller),
            multiSigSigners,
            2 // Required confirmations
        );
        uniswapAdapter = new UniswapV3Adapter();
        
        // Configure vault
        vault.setAIController(address(controller));
        vault.setFeeCollector(address(feeCollector));
        
        // Configure controller
        address[] memory dexes = new address[](1);
        dexes[0] = address(uniswapAdapter);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        controller.batchWhitelistDex(dexes, statuses);
        
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        controller.batchApproveTokens(tokens, statuses);
        
        vm.stopPrank();
        
        // Mint USDC to test users
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
        usdc.mint(address(vault), INITIAL_BALANCE); // For fee testing
    }
    
    // ===== Vault Tests =====
    
    function testVaultDeposit() public {
        uint256 depositAmount = 10_000e6; // 10k USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        
        uint256 sharesBefore = vault.balanceOf(user1);
        uint256 shares = vault.deposit(depositAmount, user1);
        uint256 sharesAfter = vault.balanceOf(user1);
        
        assertEq(sharesAfter - sharesBefore, shares);
        assertGt(shares, 0);
        vm.stopPrank();
    }
    
    function testVaultMinimumDeposit() public {
        uint256 belowMinimum = 0.5e6; // 0.5 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), belowMinimum);
        
        vm.expectRevert();
        vault.deposit(belowMinimum, user1);
        vm.stopPrank();
    }
    
    function testEmergencyWithdraw() public {
        // First deposit
        uint256 depositAmount = 10_000e6;
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        
        // Pause the vault
        vm.stopPrank();
        vm.prank(owner);
        vault.pause();
        
        // Emergency withdraw should still work
        vm.startPrank(user1);
        uint256 balanceBefore = usdc.balanceOf(user1);
        uint256 assets = vault.emergencyWithdraw(shares);
        uint256 balanceAfter = usdc.balanceOf(user1);
        
        assertEq(balanceAfter - balanceBefore, assets);
        assertEq(vault.balanceOf(user1), 0);
        vm.stopPrank();
    }
    
    // ===== AIWalletController Tests =====
    
    function testAIWalletSwap() public {
        vm.prank(aiWallet);
        
        // This will revert because we don't have a real DEX
        vm.expectRevert();
        controller.executeSwap(
            address(uniswapAdapter),
            address(usdc),
            address(0x123), // Some token
            1000e6,
            900e6
        );
    }
    
    function testDailyOperationLimit() public {
        // Set low limit for testing
        vm.prank(owner);
        controller.setLimits(300, 10_000_000e6, 2);
        
        // First operation should work
        vm.startPrank(aiWallet);
        vm.expectRevert(); // Will revert on actual swap, but operation count increases
        controller.executeSwap(address(uniswapAdapter), address(usdc), address(0x123), 1000e6, 900e6);
        
        // Second operation should work
        vm.expectRevert();
        controller.executeSwap(address(uniswapAdapter), address(usdc), address(0x123), 1000e6, 900e6);
        
        // Third operation should fail due to limit
        vm.expectRevert(OptimizedAIWalletController.DailyLimitExceeded.selector);
        controller.executeSwap(address(uniswapAdapter), address(usdc), address(0x123), 1000e6, 900e6);
        
        vm.stopPrank();
    }
    
    // ===== FeeCollector Tests =====
    
    function testManagementFeeCalculation() public {
        uint256 balance = 100_000e6; // 100k USDC
        
        // Initialize user
        vm.prank(address(vault));
        feeCollector.initializeUser(user1);
        
        // Warp time forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        uint256 expectedFee = (balance * 100) / 10000; // 1%
        uint256 calculatedFee = feeCollector.calculateManagementFee(user1, balance);
        
        assertEq(calculatedFee, expectedFee);
    }
    
    function testPerformanceFeeCalculation() public {
        uint256 initialBalance = 100_000e6;
        uint256 newBalance = 120_000e6; // 20% profit
        
        // Set high water mark
        vm.startPrank(address(vault));
        feeCollector.collectPerformanceFee(user1, initialBalance);
        
        // Calculate fee on profit
        uint256 expectedFee = ((newBalance - initialBalance) * 2000) / 10000; // 20% of 20k
        uint256 calculatedFee = feeCollector.calculatePerformanceFee(user1, newBalance);
        
        assertEq(calculatedFee, expectedFee);
        assertEq(calculatedFee, 4_000e6); // 4k USDC
        vm.stopPrank();
    }
    
    // ===== EmergencyModule Tests =====
    
    function testEmergencyPause() public {
        // Any authorized user can pause
        vm.prank(multiSigSigners[0]);
        emergency.pauseAIOperations();
        
        (bool aiPaused,,) = emergency.getEmergencyStatus();
        assertTrue(aiPaused);
    }
    
    function testEmergencyModeRequiresMultiSig() public {
        // Single signer cannot enable emergency mode
        vm.prank(multiSigSigners[0]);
        vm.expectRevert(OptimizedEmergencyModule.TimeDelayActive.selector);
        emergency.enableEmergencyMode();
        
        // Even with time delay, still needs multi-sig confirmations
        vm.warp(block.timestamp + 7 hours);
        vm.prank(multiSigSigners[0]);
        emergency.enableEmergencyMode(); // First confirmation
        
        // Emergency mode not yet enabled
        (,bool emergencyMode,) = emergency.getEmergencyStatus();
        assertFalse(emergencyMode);
    }
    
    // ===== Integration Tests =====
    
    function testFullDepositWithdrawFlow() public {
        uint256 depositAmount = 50_000e6;
        
        // User deposits
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        
        // Check vault balance
        assertEq(usdc.balanceOf(address(vault)), depositAmount);
        
        // User withdraws half
        uint256 halfShares = shares / 2;
        uint256 assets = vault.redeem(halfShares, user1, user1);
        
        // Check balances
        assertApproxEqAbs(assets, depositAmount / 2, 1);
        assertEq(vault.balanceOf(user1), shares - halfShares);
        vm.stopPrank();
    }
    
    function testBatchFeeCollection() public {
        // Setup users with deposits
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(vault), 200_000e6);
        vault.deposit(200_000e6, user2);
        vm.stopPrank();
        
        // Initialize fee tracking
        vm.startPrank(address(vault));
        feeCollector.initializeUser(user1);
        feeCollector.initializeUser(user2);
        
        // Warp time and collect fees
        vm.warp(block.timestamp + 30 days);
        
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        
        uint256[] memory balances = new uint256[](2);
        balances[0] = 100_000e6;
        balances[1] = 200_000e6;
        
        (uint256 mgmtFees, uint256 perfFees) = feeCollector.batchCollectFees(users, balances);
        
        assertGt(mgmtFees, 0);
        assertEq(perfFees, 0); // No profit yet
        vm.stopPrank();
    }
}