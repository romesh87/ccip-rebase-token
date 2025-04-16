// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken rebaseToken;
    Vault vault;

    address public OWNER = makeAddr("owner");
    address public USER = makeAddr("user");
    address public USER2 = makeAddr("user2");

    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    function setUp() external {
        vm.startPrank(OWNER);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function testDepositInterestIsLinear(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e5, type(uint96).max);
        // 1. deposit
        vm.startPrank(USER);
        vm.deal(USER, amountToDeposit);
        vault.deposit{value: amountToDeposit}();

        // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(USER);

        console.log("startBalance: ", startBalance);
        assertEq(startBalance, amountToDeposit);

        // 3. warp time and check balance
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(USER);

        assertGt(middleBalance, startBalance);
        // 4. warp time again by the same amount and check the balance

        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(USER);

        assertGt(endBalance, middleBalance);
        assertApproxEqAbs(middleBalance - startBalance, endBalance - middleBalance, 1);
        vm.stopPrank();
    }

    function testCanRedeemStraightAway(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 1e5, type(uint96).max);
        vm.startPrank(USER);
        vm.deal(USER, amountToDeposit);
        vault.deposit{value: amountToDeposit}();

        assertEq(rebaseToken.balanceOf(USER), amountToDeposit);

        vault.redeem(type(uint256).max);

        assertEq(rebaseToken.balanceOf(USER), 0);
        assertEq(USER.balance, amountToDeposit);
        vm.stopPrank();
    }

    function testCanRedeemAfterSomeTimeHasPassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        vm.deal(USER, depositAmount);

        vm.prank(USER);
        vault.deposit{value: depositAmount}();

        vm.warp(block.timestamp + time);
        uint256 tokenBalanceAfterSomeTime = rebaseToken.balanceOf(USER);
        uint256 rewardsAmount = tokenBalanceAfterSomeTime - depositAmount;
        vm.deal(OWNER, rewardsAmount);

        vm.startPrank(OWNER);
        addRewardsToVault(rewardsAmount);

        vm.startPrank(USER);
        vault.redeem(tokenBalanceAfterSomeTime);

        uint256 ethBalance = USER.balance;
        assertEq(ethBalance, tokenBalanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
    }

    function testCanTransfer(uint256 amountToDeposit, uint256 amountToSend) public {
        amountToDeposit = bound(amountToDeposit, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amountToDeposit - 1e5);

        vm.deal(USER, amountToDeposit);

        vm.prank(USER);
        vault.deposit{value: amountToDeposit}();

        uint256 initialInterestRate = rebaseToken.getInterestRate();
        uint256 initialUserBalance = rebaseToken.balanceOf(USER);
        uint256 initialUser2Balance = rebaseToken.balanceOf(USER2);

        assertEq(initialUserBalance, amountToDeposit);
        assertEq(initialUser2Balance, 0);

        vm.prank(OWNER);
        rebaseToken.setInterestRate(4e10);

        vm.prank(USER);
        rebaseToken.transfer(USER2, amountToSend);

        uint256 finalUserBalance = rebaseToken.balanceOf(USER);
        uint256 finalUser2Balance = rebaseToken.balanceOf(USER2);
        uint256 user1InterestRate = rebaseToken.getUserInterestRate(USER);
        uint256 user2InterestRate = rebaseToken.getUserInterestRate(USER2);

        assertEq(finalUser2Balance, amountToSend);
        assertEq(finalUserBalance, initialUserBalance - amountToSend);
        assertEq(user1InterestRate, initialInterestRate);
        assertEq(user2InterestRate, initialInterestRate);
    }

    function testCanTransferFrom(uint256 amountToDeposit, uint256 amountToSend) public {
        amountToDeposit = bound(amountToDeposit, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amountToDeposit - 1e5);

        vm.deal(USER, amountToDeposit);

        vm.prank(USER);
        vault.deposit{value: amountToDeposit}();

        uint256 initialInterestRate = rebaseToken.getInterestRate();
        uint256 initialUserBalance = rebaseToken.balanceOf(USER);
        uint256 initialUser2Balance = rebaseToken.balanceOf(USER2);

        assertEq(initialUserBalance, amountToDeposit);
        assertEq(initialUser2Balance, 0);

        vm.prank(OWNER);
        rebaseToken.setInterestRate(4e10);

        vm.prank(USER);
        rebaseToken.approve(USER, amountToSend);

        vm.prank(USER);
        rebaseToken.transferFrom(USER, USER2, amountToSend);

        uint256 finalUserBalance = rebaseToken.balanceOf(USER);
        uint256 finalUser2Balance = rebaseToken.balanceOf(USER2);
        uint256 user1InterestRate = rebaseToken.getUserInterestRate(USER);
        uint256 user2InterestRate = rebaseToken.getUserInterestRate(USER2);

        assertEq(finalUser2Balance, amountToSend);
        assertEq(finalUserBalance, initialUserBalance - amountToSend);
        assertEq(user1InterestRate, initialInterestRate);
        assertEq(user2InterestRate, initialInterestRate);
    }

    function testCanNotSetInterestRateIfNotOwner(uint256 newInterestRate) public {
        vm.prank(USER);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 oldInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, oldInterestRate + 1, type(uint96).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector, oldInterestRate, newInterestRate
            )
        );
        vm.prank(OWNER);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotMintIfRoleIsNotAssigned() public {
        vm.prank(USER);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(USER, 100, rebaseToken.getInterestRate());
    }

    function testCannotBurnIfRoleIsNotAssigned() public {
        vm.prank(USER);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(USER, 100);
    }

    function testCanGetPrincipalAmount(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, 2e5, type(uint96).max);
        vm.deal(USER, amountToDeposit);

        vm.prank(USER);
        vault.deposit{value: amountToDeposit}();

        assertEq(rebaseToken.principalBalanceOf(USER), amountToDeposit);

        vm.warp(block.timestamp + 1 days);

        assertEq(rebaseToken.principalBalanceOf(USER), amountToDeposit);
    }

    function testCanGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseToken(), address(rebaseToken));
    }

    ////////////////////////
    // Helper functions   //
    ////////////////////////

    function addRewardsToVault(uint256 rewardsAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardsAmount}("");
        if (!success) return;
    }
}
