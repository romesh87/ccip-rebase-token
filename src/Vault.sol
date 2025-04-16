// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

/**
 * @author  Roman Shishkin.
 * @title   Vault
 * @dev     A contract that interacts with the RebaseToken to mint and burn tokens based on ETH deposits and redemptions.
 * @notice  Allows users to deposit ETH to receive RebaseToken, redeem tokens for ETH, and supports adding rewards via ETH deposits.
 */
contract Vault {
    //////////////
    // Errors   //
    //////////////

    error Vault__RedeemFailed();

    ///////////////////////
    // State variables   //
    ///////////////////////

    IRebaseToken private immutable i_rebaseToken;

    //////////////
    // Events   //
    //////////////

    event Deposit(address indexed user, uint256 indexed amount);
    event Redeem(address indexed user, uint256 indexed amount);

    ///////////////////
    // Constructor   //
    ///////////////////

    /**
     * @notice  Initializes the Vault contract with a RebaseToken address.
     * @dev     Sets the immutable RebaseToken interface for minting and burning operations.
     * @param   _rebaseToken  The address of the RebaseToken contract.
     */
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    //////////////////////////////////////
    // Receive & fallback functions     //
    //////////////////////////////////////

    /**
     * @notice  Allows the contract to receive ETH directly, enabling reward additions.
     * @dev     Acts as a fallback for ETH transfers to the vault, such as for adding rewards.
     */
    receive() external payable {}

    //////////////////////////
    // External functions   //
    //////////////////////////

    /**
     * @notice  Deposits ETH into the vault and mints an equivalent amount of RebaseToken to the sender.
     * @dev     Calls the RebaseToken mint function with the deposited ETH amount and emits a Deposit event.
     */
    function deposit() external payable {
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice  Redeems a specified amount of RebaseToken for ETH from the vault.
     * @dev     Burns the specified amount of tokens from the sender and transfers ETH. Reverts if the ETH transfer fails.
     * @param   _amount  The amount of tokens to burn and ETH to withdraw.
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = IRebaseToken(i_rebaseToken).balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    ////////////////////////////////////////
    // External & public view functions   //
    ////////////////////////////////////////

    /**
     * @notice  Returns the address of the RebaseToken contract associated with this vault.
     * @dev     Provides a way to query the linked RebaseToken instance.
     * @return  address  The address of the RebaseToken contract.
     */
    function getRebaseToken() external view returns (address) {
        return address(i_rebaseToken);
    }
}
