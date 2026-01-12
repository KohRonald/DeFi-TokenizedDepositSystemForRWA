// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title RWAShareToken
 * @author Ronald Koh
 * @notice This contract is the ERC20 representation of the underlying RWAToken
 * @notice RWAShareToken is the "deposited/yield-bearing version" of RWAToken
 */
contract RWAShareToken is ERC20Burnable, Ownable {
    ///////////
    // ERROR //
    ///////////
    error RWAShareToken__AmountMustBeMoreThanZero();
    error RWAShareToken__BurnAmountExceedsBalance();
    error RWAShareToken__AddressZeroRestrictedFromMinting();

    constructor(string memory tokenName)
        ERC20(string.concat(tokenName, "ShareToken"), string.concat("sRWA-", tokenName))
        Ownable(msg.sender)
    {}

    //////////////////////
    // PUBLIC FUNCTIONS //
    //////////////////////
    /**
     * @notice This functions burns token after performing validations
     * @param _amount Amount of tokens to burn
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert RWAShareToken__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert RWAShareToken__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    /**
     * @notice This functions mints token after performing validations
     * @param _to Address to receive minted token
     * @param _amount Amount of tokens to mint
     * @return bool Return boolean value on mint validation
     */
    function mint(address _to, uint256 _amount) public onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert RWAShareToken__AddressZeroRestrictedFromMinting();
        }
        if (_amount >= 0) {
            revert RWAShareToken__AmountMustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
