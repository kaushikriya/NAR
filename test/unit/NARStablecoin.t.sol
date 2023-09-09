//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {NARStablecoin} from '../../src/NARStablecoin.sol';
import {Test} from 'forge-std/Test.sol';

contract NARStablecoinTest is Test {
    NARStablecoin narsc;
    address USER;

    function setUp() public {
         narsc= new NARStablecoin();
    }

    // Tests for mint

    function testRevertMintIfAmountZero() external {
        vm.startPrank(narsc.owner());
        vm.expectRevert(NARStablecoin.NAR_mustBeMoreThanZero.selector);
        narsc.mint(address(this), 0);
        vm.stopPrank();
    }

    function testRevertMintIfAddressInvalid() external {
        vm.startPrank(narsc.owner());
        vm.expectRevert(NARStablecoin.NAR_addressInvalid.selector);
        narsc.mint(address(0), 10 ether);
        vm.stopPrank();
    }

    function testShouldMintNAR() external {
        vm.startPrank(narsc.owner());
        narsc.mint(address(this), 10 ether);
        uint256 balance= narsc.balanceOf(address(this));
        assertEq(balance, 10 ether);
        vm.stopPrank();
    }

    function testRevertMintIfNotOwner() external {
        vm.startPrank(address(1));
        vm.expectRevert();
        narsc.mint(address(this), 10 ether);
        vm.stopPrank();
    }

    // Tests for burn

    function testRevertBurnIfAmountZero() external {
        vm.startPrank(narsc.owner());
        vm.expectRevert(NARStablecoin.NAR_mustBeMoreThanZero.selector);
        narsc.burn(0);
        vm.stopPrank();
    }

    function testRevertMintIfInsufficientBalance() external {
        vm.startPrank(narsc.owner());
        narsc.mint(address(this), 1 ether);
        vm.expectRevert(NARStablecoin.NAR_notEnoughBalance.selector);
        narsc.burn(10 ether);
        vm.stopPrank();
    }

    function testShouldBurnNAR() external {
        vm.startPrank(narsc.owner());
        narsc.mint(address(this), 10 ether);
        uint256 balance= narsc.balanceOf(address(this));
        narsc.burn(1 ether);
        uint256 balanceAfter= narsc.balanceOf(address(this));
        assertEq(balance, balanceAfter+ 1 ether);
        vm.stopPrank();
    }

    function testRevertIfNotOwner() external {
        vm.startPrank(address(1));
        vm.expectRevert();
        narsc.burn(10 ether);
        vm.stopPrank();
    }
}