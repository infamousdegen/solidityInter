        /* -------------------------------------------------------------------
       |                      Test based on example                             |
       | ________________________________________________________________ | */

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/StakingBank.sol";
import "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import "forge-std/console.sol";

contract StakingTestExample is Test {
    Staking public staking;
    ERC20Mock public mock;

    address public owner = address(0x1337);

    address public depositor1 = address(0x69420);
    
    address public depositor2 = address(0x5544);


    //erros
    error timePassed();
    error withdrawLocked();


    function setUp() public {
        vm.label(owner,"Owner");
        vm.label(depositor1,"user1");
        vm.label(depositor2,"user2");
        vm.startPrank(owner);

        mock = new ERC20Mock("MOCK","MCK",owner,1000 * 10**18);

        mock.mint(depositor1, 1000 *10**18);
        mock.mint(depositor2, 4000 * 10**18);

        staking = new Staking(mock,86400);
        mock.transfer(address(staking), 1000 * 10**18);
        vm.stopPrank();

        vm.prank(depositor1);
        mock.approve(address(staking), type(uint256).max);

        vm.prank(depositor2);
        mock.approve(address(staking), type(uint256).max);
    }


    function test_deposit_depositor1() public {

        vm.startPrank(depositor1);
        staking.deposit(1000 *10**18, depositor1);
        vm.stopPrank();
    }

    function test_deposit_depositor2() public {

        vm.startPrank(depositor2);
        staking.deposit(4000 *10**18, depositor2);
        vm.stopPrank();
    }

    function test_redeem_depositor1() public{
        vm.startPrank(depositor1);
        vm.warp(staking.deploymentTime() + (2*staking.timeConstant()) +1);
        staking.redeem(staking.balanceOf(depositor1), depositor1, depositor1);
        vm.stopPrank();
    }

    function test_redeem_depositor2() public{
        vm.startPrank(depositor2);
        vm.warp(staking.deploymentTime() + (3*staking.timeConstant()) +1);

        staking.redeem(staking.balanceOf(depositor2), depositor2, depositor2);
        vm.stopPrank();
    }

    function test_owner_withdraw() public {
        vm.startPrank(owner);
        vm.warp(staking.deploymentTime() + (4*staking.timeConstant()) +1);
        staking.ownerWithdraw(address(owner));
        assertEq(mock.balanceOf(owner),500 * 10**18);

    }

    function test_final() public {
        test_deposit_depositor1();
        test_deposit_depositor2();
        test_redeem_depositor1();
        test_redeem_depositor2();
        test_owner_withdraw();

    }

}