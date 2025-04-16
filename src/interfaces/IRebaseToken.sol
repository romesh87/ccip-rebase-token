// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/**
 * @title   IRebaseToken
 * @notice  Interface for the RebaseToken contract, a cross-chain rebase token with interest-bearing mechanics.
 * @dev     Defines the external and public functions and events for interacting with the RebaseToken contract.
 */
interface IRebaseToken {
    //////////////
    // Events   //
    //////////////

    /**
     * @notice  Emitted when the global interest rate is updated.
     * @param   newInterestRate  The new interest rate set (per second).
     */
    event InterestRateSet(uint256 indexed newInterestRate);

    //////////////////////////
    // External functions   //
    //////////////////////////

    /**
     * @notice  Grants the mint and burn role to a specified account.
     * @param   _account  The address to receive the MINT_AND_BURN_ROLE.
     */
    function grantMintAndBurnRole(address _account) external;

    /**
     * @notice  Sets a new global interest rate for the token.
     * @param   _newInterestRate  The new interest rate (per second) to set.
     */
    function setInterestRate(uint256 _newInterestRate) external;

    /**
     * @notice  Mints new tokens to a specified address.
     * @param   _to  The address to receive the newly minted tokens.
     * @param   _amount  The amount of tokens to mint.
     * @param   _amount  The interest rate that should be assigned to the user.
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external;

    /**
     * @notice  Burns tokens from a specified address.
     * @param   _from  The address from which tokens will be burned.
     * @param   _amount  The amount of tokens to burn (or max uint256 for full balance).
     */
    function burn(address _from, uint256 _amount) external;

    /**
     * @notice  Returns the principal balance of a user (excluding accrued interest).
     * @param   _user  The address to query the principal balance for.
     * @return  uint256  The principal balance of the user.
     */
    function principalBalanceOf(address _user) external view returns (uint256);

    /**
     * @notice  Returns the current global interest rate.
     * @return  uint256  The current global interest rate (per second).
     */
    function getInterestRate() external view returns (uint256);

    /**
     * @notice  Returns the interest rate assigned to a specific user.
     * @param   _user  The address to query the interest rate for.
     * @return  uint256  The user's interest rate (per second).
     */
    function getUserInterestRate(address _user) external view returns (uint256);

    //////////////////////////
    // Public functions     //
    //////////////////////////

    /**
     * @notice  Transfers tokens to a recipient, accounting for accrued interest.
     * @param   _recipient  The address to receive the tokens.
     * @param   _amount  The amount of tokens to transfer (or max uint256 for full balance).
     * @return  bool  True if the transfer succeeds.
     */
    function transfer(address _recipient, uint256 _amount) external returns (bool);

    /**
     * @notice  Transfers tokens from one address to another, accounting for accrued interest.
     * @param   _sender  The address sending the tokens.
     * @param   _recipient  The address receiving the tokens.
     * @param   _amount  The amount of tokens to transfer (or max uint256 for full balance).
     * @return  bool  True if the transfer succeeds.
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool);

    /**
     * @notice  Returns the total balance of a user, including accrued interest.
     * @param   _user  The address to query the total balance for.
     * @return  uint256  The total balance, including principal and accrued interest.
     */
    function balanceOf(address _user) external view returns (uint256);
}
