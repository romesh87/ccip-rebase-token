// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {Client} from "ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract BridgeTokens is Script {
    function run(
        address routerAddress,
        uint64 remoteChainSelector,
        address receiver,
        uint256 amountToBridge,
        address localTokenAddress,
        address linkTokenAddress
    ) public {
        vm.startBroadcast();
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: localTokenAddress, amount: amountToBridge});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });

        // Get LINK fee
        uint256 fee = IRouterClient(routerAddress).getFee(remoteChainSelector, message);

        // Approvals
        IERC20(linkTokenAddress).approve(routerAddress, fee);
        IERC20(address(localTokenAddress)).approve(routerAddress, amountToBridge);

        // Send message
        IRouterClient(routerAddress).ccipSend(remoteChainSelector, message);

        vm.stopBroadcast();
    }
}
