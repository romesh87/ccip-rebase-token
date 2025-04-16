// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {Vault} from "src/Vault.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

contract TokenAndPoolDeployer is Script {
    function run() public returns (RebaseToken, RebaseTokenPool) {
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startBroadcast();
        RebaseToken token = new RebaseToken();
        console.log("Sepolia Rebase Token Address: %s", address(token));
        RebaseTokenPool rebaseTokenPool = new RebaseTokenPool(
            IERC20(address(token)), new address[](0), networkDetails.rmnProxyAddress, networkDetails.routerAddress
        );
        console.log("Sepolia Pool Address: %s", address(rebaseTokenPool));

        token.grantMintAndBurnRole(address(rebaseTokenPool));

        RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(address(token));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(token));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(address(token), address(rebaseTokenPool));
        vm.stopBroadcast();

        return (token, rebaseTokenPool);
    }
}

contract VaultDeployer is Script {
    function run(address _rebaseToken) public returns (Vault) {
        vm.startBroadcast();
        Vault vault = new Vault(IRebaseToken(_rebaseToken));
        console.log("Sepolia Vault Address: %s", address(vault));
        IRebaseToken(_rebaseToken).grantMintAndBurnRole(address(vault));

        vm.stopBroadcast();

        return vault;
    }
}
