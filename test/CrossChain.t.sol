// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {IERC20} from "ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {Client} from "ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {Vault} from "src/Vault.sol";

contract CrossChainTest is Test {
    address public OWNER = makeAddr("owner");
    address public USER = makeAddr("user");

    uint256 SEND_VALUE = 1e5;

    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken ethSepoliaToken;
    RebaseToken arbSepoliaToken;

    Vault vault;

    RebaseTokenPool ethSepoliaTokenPool;
    RebaseTokenPool arbSepoliaTokenPool;

    Register.NetworkDetails ethSepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        ethSepoliaFork = vm.createFork(vm.envString("ETH_SEPOLIA_RPC_URL"));
        arbSepoliaFork = vm.createFork(vm.envString("ARB_SEPOLIA_RPC_URL"));

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Deploy & configure on Eth Sepolia
        vm.selectFork(ethSepoliaFork);
        ethSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(OWNER);
        // 1. Deploy token
        ethSepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(ethSepoliaToken)));
        // 2. Deploy token pool
        ethSepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(ethSepoliaToken)),
            new address[](0),
            ethSepoliaNetworkDetails.rmnProxyAddress,
            ethSepoliaNetworkDetails.routerAddress
        );
        // 3 Claim Mint and Burn Roles
        ethSepoliaToken.grantMintAndBurnRole(address(vault));
        ethSepoliaToken.grantMintAndBurnRole(address(ethSepoliaTokenPool));
        // 4. Claim and Accept the Admin Role
        RegistryModuleOwnerCustom(ethSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(ethSepoliaToken)
        );
        TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(ethSepoliaToken));
        // 5. Link Token to Pool
        TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(ethSepoliaToken), address(ethSepoliaTokenPool)
        );
        vm.stopPrank();

        // Deploy & configure on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(OWNER);
        // 1. Deploy token
        arbSepoliaToken = new RebaseToken();
        // 2. Deploy Token Pool
        arbSepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        // 3 Claim Mint and Burn Roles
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaTokenPool));
        // 4. Claim and Accept the Admin Role
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        // 5. Link Token to Pool
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaTokenPool)
        );
        vm.stopPrank();

        // Configure Token Pools
        configureTokenPool(
            ethSepoliaFork,
            address(ethSepoliaTokenPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaTokenPool),
            address(arbSepoliaToken)
        );
        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaTokenPool),
            ethSepoliaNetworkDetails.chainSelector,
            address(ethSepoliaTokenPool),
            address(ethSepoliaToken)
        );
    }

    function testBridgeAllTokens() public {
        vm.selectFork(ethSepoliaFork);
        vm.deal(USER, SEND_VALUE);

        vm.prank(USER);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        assertEq(ethSepoliaToken.balanceOf(USER), SEND_VALUE);
        bridgeTokens(
            SEND_VALUE,
            ethSepoliaFork,
            arbSepoliaFork,
            ethSepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            ethSepoliaToken,
            arbSepoliaToken
        );

        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes);
        bridgeTokens(
            arbSepoliaToken.balanceOf(USER),
            arbSepoliaFork,
            ethSepoliaFork,
            arbSepoliaNetworkDetails,
            ethSepoliaNetworkDetails,
            arbSepoliaToken,
            ethSepoliaToken
        );
    }

    /////////////////////////
    // Helper functions    //
    /////////////////////////

    function configureTokenPool(
        uint256 fork,
        address localPoolAddress,
        uint64 remoteChainSelector,
        address remotePoolAddress,
        address remoteTokenAddress
    ) public {
        vm.selectFork(fork);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePoolAddress),
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        vm.prank(OWNER);
        RebaseTokenPool(localPoolAddress).applyChainUpdates(chainsToAdd);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(USER),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: false}))
        });

        // Get LINK fee
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(USER, fee);

        // Approvals
        vm.prank(USER);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        vm.prank(USER);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        // Send message
        uint256 localBalanceBefore = localToken.balanceOf(USER);

        vm.prank(USER);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        uint256 localBalanceAfter = localToken.balanceOf(USER);
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);
        uint256 localUserInterestRate = localToken.getUserInterestRate(USER);

        // Propagate message
        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(USER);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        uint256 remoteBalanceAfter = remoteToken.balanceOf(USER);
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(USER);
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge);
        assertEq(localUserInterestRate, remoteUserInterestRate);
    }
}
