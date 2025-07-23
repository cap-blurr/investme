// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UniswapV3Adapter} from "../src/UniswapV3Adapter.sol";
import {OptimizedAIWalletController} from "../src/AIWalletController.sol";
import {OptimizedFeeCollector} from "../src/FeeCollector.sol";
import {OptimizedEmergencyModule} from "../src/EmergencyModule.sol";
import {OptimizedVault} from "../src/Vault.sol";

contract MockERC20 is IERC20 {
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

contract MockSwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256) {
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        IERC20(params.tokenOut).transfer(params.recipient, params.amountIn * 2);
        return params.amountIn * 2;
    }
}

contract MockPositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        IERC20(params.token0).transferFrom(msg.sender, address(this), params.amount0Desired);
        IERC20(params.token1).transferFrom(msg.sender, address(this), params.amount1Desired);
        return (1, uint128(params.amount0Desired + params.amount1Desired), params.amount0Desired, params.amount1Desired);
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable returns (uint256 amount0, uint256 amount1) {
        return (params.liquidity, params.liquidity);
    }

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1) {
        return (10, 20);
    }

    function positions(uint256) external pure returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    ) {
        return (0, address(0), address(0), address(0), 0, 0, 0, 100, 0, 0, 1, 2);
    }
}

contract MockVault {
    mapping(address => uint256) public balances;

    function setBalance(address user, uint256 bal) external {
        balances[user] = bal;
    }

    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }

    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }
}

contract CoverageTest is Test {
    address constant SWAP_ROUTER_ADDR = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant POSITION_MANAGER_ADDR = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    UniswapV3Adapter adapter;
    MockERC20 tokenA;
    MockERC20 tokenB;

    function setUp() public {
        adapter = new UniswapV3Adapter();
        tokenA = new MockERC20();
        tokenB = new MockERC20();

        // Deploy mocks at the expected Uniswap addresses
        MockSwapRouter router = new MockSwapRouter();
        vm.etch(SWAP_ROUTER_ADDR, address(router).code);
        MockPositionManager manager = new MockPositionManager();
        vm.etch(POSITION_MANAGER_ADDR, address(manager).code);

        // Ensure router has output tokens to send
        tokenB.mint(SWAP_ROUTER_ADDR, 1_000_000e6);

        tokenA.mint(address(this), 1_000_000e6);
        tokenB.mint(address(this), 1_000_000e6);
        tokenA.approve(address(adapter), type(uint256).max);
        tokenB.approve(address(adapter), type(uint256).max);
    }

    function testUniswapAdapterSwap() public {
        uint256 out = adapter.swap(address(tokenA), address(tokenB), 1000, 1);
        assertEq(out, 2000);
    }

    function testUniswapAdapterLiquidityFlow() public {
        uint256 id = adapter.addLiquidity(address(tokenA), address(tokenB), 500, 500, -600, 600);
        (uint256 amount0, uint256 amount1) = adapter.removeLiquidity(id, 100);
        assertEq(amount0, 100);
        assertEq(amount1, 100);
        (amount0, amount1) = adapter.collectFees(id);
        assertEq(amount0, 10);
        assertEq(amount1, 20);
        uint256 value = adapter.getPositionValue(id);
        assertEq(value, 103);
    }

    function testControllerAndFeeCollector() public {
        MockVault v = new MockVault();
        OptimizedAIWalletController controller = new OptimizedAIWalletController(address(v), address(this));
        OptimizedFeeCollector collector = new OptimizedFeeCollector(address(v), address(this));
        controller.setEmergencyModule(address(0x123));
        controller.transferOwnership(address(this));
        controller.setAIWallet(address(this));
        address[] memory dexes = new address[](1);
        dexes[0] = address(adapter);
        bool[] memory stats = new bool[](1);
        stats[0] = true;
        controller.batchWhitelistDex(dexes, stats);
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        bool[] memory approveStats = new bool[](2);
        approveStats[0] = true;
        approveStats[1] = true;
        controller.batchApproveTokens(tokens, approveStats);
        controller.setLimits(100, 1_000_000e6, 5);
        controller.pause();
        controller.unpause();
        vm.prank(address(this));
        controller.recordOperation();

        // Fee collector logic
        v.setBalance(address(this), 1000);
        tokenA.mint(address(v), 1000);
        vm.prank(address(v));
        tokenA.approve(address(collector), 1000);
        collector.initializeUser(address(this));
        vm.warp(block.timestamp + 365 days);
        uint256 mgmt = collector.collectManagementFee(address(this), 1000);
        uint256 perf = collector.collectPerformanceFee(address(this), 1500);
        assertGt(mgmt, 0);
        assertGt(perf, 0);
        collector.transferCollectedFees(address(tokenA));
        collector.setFeeRecipient(address(0xdead));
        collector.transferOwnership(address(0x456));
    }

    function testVaultAuthorization() public {
        OptimizedVault vault = new OptimizedVault();
        vault.initialize(address(tokenA), address(this));
        assertTrue(vault.isAuthorized(address(this)));
        vm.prank(address(this));
        vault.pause();
        vm.expectRevert();
        vault.deposit(1e6, address(this));
        vault.unpause();
        tokenA.approve(address(vault), 1e6);
        vault.deposit(1e6, address(this));
        vault.syncPrefundedAssets(address(this));
    }
}

