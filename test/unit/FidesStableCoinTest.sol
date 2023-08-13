// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {FidesStableCoin} from "../../src/FidesStableCoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract FidesStablecoinTest is StdCheats, Test {
    FidesStableCoin fsc;

    function setUp() public {
        fsc = new FidesStableCoin();
    }

    function testMustMintMoreThanZero() public {
        vm.prank(fsc.owner());
        vm.expectRevert();
        fsc.mint(address(this), 0);
    }

    function testMustBurnMoreThanZero() public {
        vm.startPrank(fsc.owner());
        fsc.mint(address(this), 100);
        vm.expectRevert();
        fsc.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(fsc.owner());
        fsc.mint(address(this), 100);
        vm.expectRevert();
        fsc.burn(101);
        vm.stopPrank();
    }

    function testCantMintToZeroAddress() public {
        vm.startPrank(fsc.owner());
        vm.expectRevert();
        fsc.mint(address(0), 100);
        vm.stopPrank();
    }
}