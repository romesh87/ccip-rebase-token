// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @author  Roman Shishkin.
 * @title   Rebase Token.
 * @notice  This is a cross-chain rebase token that incentivises users to deposit into a vault
 *          and gain interest in rewards. The interest rate in the smart contract can only decrease.
 *          Each user will have their own interest rate that is the global interest rate at the time of
 *          depositing.
 * @dev     Inherits from ERC20 for token functionality, Ownable for ownership control, and
 *          AccessControl for role-based permissions (e.g., minting and burning).
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    //////////////
    // Errors   //
    //////////////

    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    ///////////////////////
    // State variables   //
    ///////////////////////

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8; // Interest rate per second (0.00000005 token / second)
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    //////////////
    // Events   //
    //////////////

    event InterestRateSet(uint256 indexed newInterestRate);

    ///////////////////
    // Constructor   //
    ///////////////////

    /**
     * @notice  Initializes the RebaseToken contract with a name, symbol, and owner.
     * @dev     Sets up the ERC20 token with "Rebase Token" (RBT) and assigns ownership to the deployer.
     */
    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {
        _grantRole(AccessControl.DEFAULT_ADMIN_ROLE, msg.sender);
    }

    //////////////////////////
    // External functions   //
    //////////////////////////

    /**
     * @notice  Grants the mint and burn role to a specified account.
     * @dev     Only callable by the contract owner. Uses AccessControl's grantRole function.
     * @param   _account  The address to receive the MINT_AND_BURN_ROLE.
     */
    function grantMintAndBurnRole(address _account) external onlyOwner {
        grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice  Sets a new global interest rate for the token.
     * @dev     Only callable by the owner. The new rate must be less than or equal to the current rate.
     *          Emits an InterestRateSet event upon success.
     * @param   _newInterestRate  The new interest rate (per second) to set.
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate > s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice  Mints new tokens to a specified address.
     * @dev     Only callable by an address with MINT_AND_BURN_ROLE. Updates accrued interest
     *          before minting and assigns the current global interest rate to the recipient.
     * @param   _to  The address to receive the newly minted tokens.
     * @param   _amount  The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice  Burns tokens from a specified address.
     * @dev     Only callable by an address with MINT_AND_BURN_ROLE. Updates accrued interest
     *          before burning. If _amount is max uint256, burns the entire balance.
     * @param   _from  The address from which tokens will be burned.
     * @param   _amount  The amount of tokens to burn (or max uint256 for full balance).
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // Account for dust
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    //////////////////////////
    // Public functions     //
    //////////////////////////

    /**
     * @notice  Transfers tokens to a recipient, accounting for accrued interest.
     * @dev     Overrides ERC20's transfer function. Updates interest for both sender and recipient.
     *          If recipient is new, they inherit the sender's interest rate.
     * @param   _recipient  The address to receive the tokens.
     * @param   _amount  The amount of tokens to transfer (or max uint256 for full balance).
     * @return  bool  True if the transfer succeeds.
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        // Account for dust
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        // If the recipient is new user, they inherit the sender's interest rate
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }

        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice  Transfers tokens from one address to another, accounting for accrued interest.
     * @dev     Overrides ERC20's transferFrom function. Updates interest for both sender and recipient.
     *          If recipient is new, they inherit the sender's interest rate.
     * @param   _sender  The address sending the tokens.
     * @param   _recipient  The address receiving the tokens.
     * @param   _amount  The amount of tokens to transfer (or max uint256 for full balance).
     * @return  bool  True if the transfer succeeds.
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        // Account for dust
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        // If the recipient is new user, they inherit the sender's interest rate
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }

        return super.transferFrom(_sender, _recipient, _amount);
    }

    //////////////////////////
    // Internal functions   //
    //////////////////////////

    /**
     * @notice  Mints accrued interest to a user based on their principal balance and elapsed time.
     * @dev     Updates the user's balance with interest and resets their last updated timestamp.
     * @param   _user  The address for which to mint accrued interest.
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 currentBalance = super.balanceOf(_user);
        uint256 currentBalanceIncludingInterest = balanceOf(_user);
        uint256 amountToBeMinted = currentBalanceIncludingInterest - currentBalance;
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, amountToBeMinted);
    }

    /////////////////////////////////////////
    // Internal & private view functions   //
    /////////////////////////////////////////

    /**
     * @notice  Calculates the accumulated interest factor for a user since their last update.
     * @dev     Returns a factor (1e18 + interest) representing linear growth over time.
     * @param   _user  The address to calculate interest for.
     * @return  uint256  The interest factor (PRECISION_FACTOR + accrued interest).
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];

        return (PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed));
    }

    ////////////////////////////////////////
    // External & public view functions   //
    ////////////////////////////////////////

    /**
     * @notice  Returns the principal balance of a user (excluding accrued interest).
     * @dev     Calls the parent ERC20 balanceOf function to get the minted token balance.
     * @param   _user  The address to query the principal balance for.
     * @return  uint256  The principal balance of the user.
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice  Returns the current global interest rate.
     * @dev     Provides the interest rate applied to new deposits.
     * @return  uint256  The current global interest rate (per second).
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice  Returns the interest rate assigned to a specific user.
     * @dev     Retrieves the user's personal interest rate set at deposit time.
     * @param   _user  The address to query the interest rate for.
     * @return  uint256  The user's interest rate (per second).
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice  Returns the total balance of a user, including accrued interest.
     * @dev     Overrides ERC20's balanceOf to include interest accrued since last update.
     * @param   _user  The address to query the total balance for.
     * @return  uint256  The total balance, including principal and accrued interest.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }
}
