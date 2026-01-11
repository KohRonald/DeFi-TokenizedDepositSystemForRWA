// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title RWAToken
 * @author Ronald Koh
 * @notice This contract is the ERC20 representation of the underlying asset
 * @notice RWAToken acts as the "base asset"
 * @notice Minting and Burning of RWAToken is handled here, ETH is stored in this contract
 */
contract RWAToken is ERC20Burnable, Ownable {
    ///////////
    // ERROR //
    ///////////
    error RWAToken__AmountMustBeMoreThanZero();
    error RWAToken__BurnAmountExceedsBalance();
    error RWAToken__ETHTransferFailed();
    error RWAToken__InsufficientETHAmount();
    error RWAToken__AddressZeroRestrictedFromMinting();

    constructor() ERC20("GoldToken", "Gold") Ownable(msg.sender) {}

    ///////////////////////
    // External Fuctions //
    ///////////////////////

    /**
     * @notice This functions burns token after performing validations
     * @param _amount Amount of tokens to burn
     */
    function burn(uint256 _amount) public override {
        uint256 balance = balanceOf(msg.sender);

        if (_amount == 0) revert RWAToken__AmountMustBeMoreThanZero();
        if (balance < _amount) revert RWAToken__BurnAmountExceedsBalance();

        super._burn(msg.sender, _amount);
        (bool success,) = address(msg.sender).call{value: _amount}("");
        if (!success) revert RWAToken__ETHTransferFailed();
    }

    /**
     * @notice This functions mints token after performing validations
     * @param _amount Amount of tokens to mint
     */
    function mint(uint256 _amount) public payable {
        if (msg.value == 0) revert RWAToken__InsufficientETHAmount();
        if (_amount <= 0) revert RWAToken__AmountMustBeMoreThanZero();

        //TODO: Before mint, get the price of the RWA then calculate how much can be minted

        _mint(msg.sender, _amount);
    }
}
