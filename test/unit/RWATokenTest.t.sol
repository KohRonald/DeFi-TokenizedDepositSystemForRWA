// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "lib/forge-std/src/Test.sol";
import {RWAToken} from "src/RWAToken.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {HelperConfig} from "script/HelperConfig.sol";

/**
 * @title RWATokenTest
 * @author Ronald Koh
 * @notice Unit test cases for RWAToken Contract
 */
contract RWATokenTest is Test {
    RWAToken rwaToken;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address assetUsdPriceFeed;

    string public tokenName = "Gold";
    uint256 constant ZERO_ETH_AMOUNT = 0;
    uint256 constant ETH_AMOUNT = 10 ether;
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");

    function setUp() public {
        helperConfig = new HelperConfig();
        (ethUsdPriceFeed, assetUsdPriceFeed) = helperConfig.activeNetworkConfig();

        vm.startPrank(owner);
        rwaToken = new RWAToken(tokenName, ethUsdPriceFeed, assetUsdPriceFeed);
        vm.stopPrank();

        vm.deal(address(rwaToken), 100 ether); //Prefund the RWAToken contract
    }

    function testThatAliceCanMint() public {
        //Arrange
        vm.deal(alice, ETH_AMOUNT);
        uint256 ethBalanceBefore = alice.balance;

        //Act
        vm.prank(alice);
        rwaToken.mint{value: 1e5}();
        uint256 ethBalanceAfter = alice.balance;

        //Assert
        assertGt(rwaToken.balanceOf(alice), 0);
        assertLt(ethBalanceAfter, ethBalanceBefore);
    }

    function testThatAliceDoesNotHaveSufficientEthToMint() public {
        //Arrange
        vm.deal(alice, ZERO_ETH_AMOUNT);

        //Act, Assert
        vm.expectRevert(RWAToken.RWAToken__InsufficientETHAmount.selector);
        vm.prank(alice);
        rwaToken.mint{value: 0}();
    }

    function testThatAliceCanWithdrawEth() public {
        //Arrange
        vm.deal(alice, ETH_AMOUNT);

        //Act
        vm.prank(alice);
        rwaToken.mint{value: 0.1 ether}();
        uint256 ethBalanceAfterMint = alice.balance;
        uint256 rwaTokenMinted = rwaToken.balanceOf(alice);

        vm.prank(alice);
        rwaToken.burn(rwaTokenMinted);
        uint256 ethBalanceAfterBurn = alice.balance;

        //Assert
        assertGt(ethBalanceAfterBurn, ethBalanceAfterMint); //Assert that eth balance is higher after burning
        assertEq(rwaToken.balanceOf(alice), 0); //Assert that RWATokens are all burned
    }
}
