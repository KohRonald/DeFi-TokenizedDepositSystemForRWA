// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RWAToken} from "src/RWAToken.sol";
import {RWAShareToken} from "src/RWAShareToken.sol";

/**
 * @title TokenizedDepositEngine
 * @author Ronald Koh
 *
 *  The Tokenized Deposit Engine should always be "overcollaterized". At no point should the value of all the collateral be <= the $ backed value of all the RWA Collateral Token.
 *
 *  A user has to exchange their ETH for RWA Token, then exchange the RWA Token for the RWA Share Token.
 *
 * @notice This contract is the core of the Tokenized Deposit system.
 * @notice It handles all the logic for minting and redeeming RWA Share Token, as well as depositing & withdrawing collateral.
 * @notice RWAToken is the collateral and is stored in this contract
 */
contract TokenizedDepositEngine {
    constructor() {}
}
