// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {WETH9} from "../../contracts/WETH9.sol";
import "forge-std/Test.sol";

contract WETH9Test is Test {
    WETH9 private weth;
    address private userA = makeAddr("userA");
    address private userB = makeAddr("userB");
    uint256 private initialBalance = 100 ether;

    function setUp() public {
        weth = new WETH9();
        vm.deal(userA, initialBalance);
        vm.deal(userB, initialBalance);
    }

    function test_constructor() public {
        assertEq(weth.name(), "Wrapped Camp");
        assertEq(weth.symbol(), "WCAMP");
        assertEq(weth.decimals(), 18);
        assertEq(weth.totalSupply(), 0);
    }

    function test_deposit() public {
        uint256 depositAmount = 1 ether;

        vm.prank(userA);
        weth.deposit{value: depositAmount}();

        assertEq(weth.balanceOf(userA), depositAmount);
        assertEq(weth.totalSupply(), depositAmount);
        assertEq(address(weth).balance, depositAmount);
    }

    function test_deposit_via_receive() public {
        uint256 depositAmount = 1 ether;

        vm.prank(userA);
        (bool success,) = address(weth).call{value: depositAmount}("");

        assertTrue(success);
        assertEq(weth.balanceOf(userA), depositAmount);
        assertEq(weth.totalSupply(), depositAmount);
        assertEq(address(weth).balance, depositAmount);
    }

    function test_withdraw() public {
        uint256 depositAmount = 1 ether;

        // First deposit
        weth.deposit{value: depositAmount}();

        uint256 initialUserBalance = address(this).balance;

        // Then withdraw
        weth.withdraw(depositAmount);

        assertEq(weth.balanceOf(address(this)), 0);
        assertEq(weth.totalSupply(), 0);
        assertEq(address(weth).balance, 0);
        assertEq(address(this).balance, initialUserBalance + depositAmount);
    }

    function test_withdraw_insufficient_balance() public {
        uint256 depositAmount = 1 ether;

        // Deposit a smaller amount
        vm.prank(userA);
        weth.deposit{value: depositAmount}();

        // Try to withdraw more than deposited
        vm.prank(userA);
        vm.expectRevert();
        weth.withdraw(depositAmount + 1);
    }

    function test_transfer() public {
        uint256 depositAmount = 1 ether;

        // First deposit
        vm.prank(userA);
        weth.deposit{value: depositAmount}();

        // Transfer to userB
        vm.prank(userA);
        bool success = weth.transfer(userB, depositAmount);

        assertTrue(success);
        assertEq(weth.balanceOf(userA), 0);
        assertEq(weth.balanceOf(userB), depositAmount);
        assertEq(weth.totalSupply(), depositAmount);
    }

    function test_approve_and_transferFrom() public {
        uint256 depositAmount = 1 ether;

        // First deposit
        vm.prank(userA);
        weth.deposit{value: depositAmount}();

        // Approve userB to spend tokens
        vm.prank(userA);
        bool success = weth.approve(userB, depositAmount);

        assertTrue(success);
        assertEq(weth.allowance(userA, userB), depositAmount);

        // userB transfers from userA to themselves
        vm.prank(userB);
        success = weth.transferFrom(userA, userB, depositAmount);

        assertTrue(success);
        assertEq(weth.balanceOf(userA), 0);
        assertEq(weth.balanceOf(userB), depositAmount);
        assertEq(weth.allowance(userA, userB), 0);
    }

    function test_approve_max_uint() public {
        // Approve userB to spend max tokens
        vm.prank(userA);
        bool success = weth.approve(userB, type(uint256).max);

        assertTrue(success);
        assertEq(weth.allowance(userA, userB), type(uint256).max);

        // Deposit some tokens
        vm.prank(userA);
        weth.deposit{value: 1 ether}();

        // userB transfers from userA to themselves
        vm.prank(userB);
        success = weth.transferFrom(userA, userB, 1 ether);

        assertTrue(success);
        assertEq(weth.balanceOf(userA), 0);
        assertEq(weth.balanceOf(userB), 1 ether);
        // Max approval should remain unchanged
        assertEq(weth.allowance(userA, userB), type(uint256).max);
    }

    function test_fuzz_deposit_withdraw(uint256 amount) public {
        // Bound the amount to something reasonable
        amount = bound(amount, 0.001 ether, 1000 ether);

        // Give the user enough ETH
        vm.deal(userA, amount);

        // Deposit
        vm.prank(userA);
        weth.deposit{value: amount}();

        assertEq(weth.balanceOf(userA), amount);
        assertEq(weth.totalSupply(), amount);

        // Withdraw
        vm.startPrank(userA);
        weth.withdraw(amount);

        assertEq(weth.balanceOf(userA), 0);
        assertEq(weth.totalSupply(), 0);
        assertEq(userA.balance, amount);
    }

    receive() external payable {}
}
