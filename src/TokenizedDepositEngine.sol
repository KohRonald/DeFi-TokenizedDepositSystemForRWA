// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RWAToken} from "src/RWAToken.sol";
import {RWAShareToken} from "src/RWAShareToken.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TokenizedDepositEngine
 * @author Ronald Koh
 *
 *  The Tokenized Deposit Engine should always be "overcollaterized". At no point should the value of all the collateral be <= the $ backed value of all the RWA Collateral Token.
 *
 *  A user has to exchange their ETH for RWA Token, then exchange the RWA Token for the RWA Share Token.
 *  Token exchange are done on a 1:1 basis, 1 RWAToken = 1RWAShareToken
 *
 * @notice This contract is the core of the Tokenized Deposit system.
 * @notice It handles all the logic for minting and redeeming RWA Share Token, as well as depositing & withdrawing collateral.
 * @notice RWAToken is the collateral and is stored in this contract
 */
contract TokenizedDepositEngine is ReentrancyGuard {
    ///////////
    // ERROR //
    ///////////
    error TokenizedDepositEngine__RWATokenAddressCannotBeAddressZero();
    error TokenizedDepositEngine__DepositAmountMustBeMoreThanZero();
    error TokenizedDepositEngine__TransferFailed();

    /////////////////////
    // STATE VARIABLES //
    /////////////////////
    mapping(address user => uint256 amountRwaTokenDeposited) private s_collateralDeposited;

    constructor() {}

    ////////////
    // EVENTS //
    ////////////
    event RWAShareToken__CollateralDeposited(address indexed from, uint256 amountDeposited);

    /**
     * @notice This function takes RWAToken and mints RWAShareToken at a 1:1 ratio
     * @dev RWAToken contract must be deployed prior to this
     * @param _rwaTokenAddress The address of RWAToken
     * @param _rwaTokensDeposited The amount of RWAToken transfered to exchange for minting
     */
    function depositRWATokenAndMintRWAShareToken(address _rwaTokenAddress, uint256 _rwaTokensDeposited) external {
        depositRwaToken(_rwaTokenAddress, _rwaTokensDeposited);
        mintRwaShareToken();
    }

    ////////////////////////
    // INTERNAL FUNCTIONS //
    ////////////////////////
    /**
     * @notice Validates deposited collateral
     */
    function depositRwaToken(address _rwaTokenAddress, uint256 _rwaTokensDeposited) internal {
        // 1. Checks
        if (_rwaTokenAddress == address(0)) revert TokenizedDepositEngine__RWATokenAddressCannotBeAddressZero();
        if (_rwaTokensDeposited == 0) revert TokenizedDepositEngine__DepositAmountMustBeMoreThanZero();

        // 2.Effects
        s_collateralDeposited[msg.sender] += _rwaTokensDeposited;
        emit RWAShareToken__CollateralDeposited(msg.sender, _rwaTokensDeposited);

        // 3.Interactions
        (bool success) = IERC20(_rwaTokenAddress).transferFrom(msg.sender, address(this), _rwaTokensDeposited);
        if (!success) revert TokenizedDepositEngine__TransferFailed();
    }

    /**
     * @notice Checks and mints RWAShareToken to msg.sender
     */
    function mintRwaShareToken() internal {}
}
