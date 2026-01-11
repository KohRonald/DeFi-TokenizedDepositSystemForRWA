// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {RWAToken} from "src/RWAToken.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title RWATokenTest
 * @author Ronald Koh
 * @notice Fuzz test cases for RWAToken Contract
 */
contract RWATokenTest is Test {
    RWAToken rwaToken;

    uint256 constant EthAmount = 1e18;
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");

    function setUp() public {
        vm.startPrank(owner);
        rwaToken = new RWAToken();
        vm.stopPrank();
    }

    function testThatAliceCanMint(uint256 _amount) public {
        //Arrange
        _amount = bound(_amount, 1e5, type(uint96).max);
        vm.deal(alice, EthAmount);
        uint256 ethBalanceBefore = alice.balance;

        //Act
        vm.prank(alice);
        rwaToken.mint{value: 1e5}(1);
        uint256 ethBalanceAfter = alice.balance;

        //Assert
        assertGt(rwaToken.balanceOf(alice), 0);
    }

    function testThatNonOwnerCannotMint(uint256 _amount) public {
        //Arrange
        _amount = bound(_amount, 1e5, type(uint96).max);
        bytes memory expectedRevertData = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice);
        vm.deal(alice, EthAmount);

        //Act & Assert
        vm.expectRevert(expectedRevertData);
        vm.prank(alice);
        rwaToken.mint(_amount);
    }
}
