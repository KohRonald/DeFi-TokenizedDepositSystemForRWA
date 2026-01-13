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
    error TokenizedDepositEngine__FailedToMintRWAShareToken();
    error TokenizedDepositEngine__UserHealthFactorIsBroken();

    /////////////////////
    // STATE VARIABLES //
    /////////////////////
    uint256 private constant INTEREST_RATE = 1.5e16; // 1.5%
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; //To adjust to appropriate health factor

    mapping(address => uint256) private s_collateralDeposited;
    mapping(address => uint256) private s_userLastDepositedTimestamp;
    mapping(address => uint256) private s_userTotalYieldGained;
    mapping(address => uint256) private s_rwaTokenMinted;

    RWAShareToken private immutable i_rwaShareToken;

    constructor() {}

    ////////////
    // EVENTS //
    ////////////
    event RWAShareToken__CollateralDeposited(address indexed from, uint256 amountDeposited);

    /**
     * @notice This function takes RWAToken and mints RWAShareToken at a 1:1 ratio
     * @dev RWAToken contract must be deployed prior to this
     * @param rwaTokenAddress The address of RWAToken
     * @param rwaTokensDeposited The amount of RWAToken transfered to exchange for minting
     */
    function depositCollateralAndMintRwaShareToken(address rwaTokenAddress, uint256 rwaTokensDeposited) public {
        _depositRwaToken(rwaTokenAddress, rwaTokensDeposited);
        _mintRwaShareToken(rwaTokensDeposited);
    }

    /**
     * @notice This function takes in amount of RWAShareTokens and calculates the amount to transfer
     * @param amountToReedem The amount of RWAShareToken to reedem
     */
    function redeemCollateralForRwaToken(uint256 amountToReedem) public {
        _burnCollateral(amountToReedem);
        _redeemCollateral(amountToReedem);
    }

    /**
     * @notice This function will liquidaite user if they go below the health factor
     */
    function _liquidate(address user) internal {}

    ////////////////////////
    // INTERNAL FUNCTIONS //
    ////////////////////////
    /**
     * @notice Validates deposited collateral
     */
    function _depositRwaToken(address _rwaTokenAddress, uint256 _rwaTokensDeposited) internal {
        // 1. Checks
        if (_rwaTokenAddress == address(0)) revert TokenizedDepositEngine__RWATokenAddressCannotBeAddressZero();
        if (_rwaTokensDeposited == 0) revert TokenizedDepositEngine__DepositAmountMustBeMoreThanZero();

        // 2.Effects

        // Calculate and track yield gained for any prior RWAShareTokens first before tracking new deposited collateral
        s_userTotalYieldGained[msg.sender] = _calculateYield(s_collateralDeposited[msg.sender]);
        s_userLastDepositedTimestamp[msg.sender] = block.timestamp;
        s_collateralDeposited[msg.sender] += _rwaTokensDeposited;
        emit RWAShareToken__CollateralDeposited(msg.sender, _rwaTokensDeposited);

        // 3.Interactions
        (bool success) = IERC20(_rwaTokenAddress).transferFrom(msg.sender, address(this), _rwaTokensDeposited);
        if (!success) revert TokenizedDepositEngine__TransferFailed();
    }

    /**
     * @notice Calculates and mints RWAShareToken to msg.sender
     */
    function _mintRwaShareToken(uint256 amountOfTokensToMint) internal {
        //2. Checks/Effects
        s_rwaTokenMinted[msg.sender] += amountOfTokensToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        //3. Interactions
        bool minted = i_rwaShareToken.mint(msg.sender, amountOfTokensToMint);
        if (!minted) revert TokenizedDepositEngine__FailedToMintRWAShareToken();
    }

    /**
     * @notice Validates and burns RWAShareToken from msg.sender
     */
    function _burnCollateral(uint256 amountToBurn) internal {}

    /**
     * @notice Calculates Collateral value, yield generated, and transfer to msg.sender
     */
    function _redeemCollateral(uint256 amountToReedem) internal {}

    /**
     * @notice Calculates the amount of yield generated
     * @dev Yield calculation check scenario:
     *
     *         Monday -> User deposit 10 RWAShareToken
     *
     *         Wednesday -> User deposit 10 RWAShareToken
     *              - Calculate yield for the Monday's 10 token
     *              - Time to calculate from is Monday
     *              - Track yield accquired and store to mapping
     *
     *         Friday -> User deposit 10 RWAShareToken
     *              - Calculate yield for the Monday+Wednesday 20 tokens
     *              - Time to calculate from is Wednesday
     *              - Track yield accquired and add to mapping
     *
     *         Sunday -> User withdraw all 30 RWAShareToken
     *              - Calculate yield for the Monday+Wednesday+Friday 30 tokens
     *              - Time to calculate from is Friday
     *              - Track yield accquired and add to mapping
     *              - Final yield accquired is yield map
     *
     */
    function _calculateYield(uint256 tokenAmount) internal returns (uint256) {}

    /**
     * @notice To check if the overall health of the user account is healthy
     * @notice A healthy account is one with more than enough collateral
     * @param user The adddress to check the health factor
     */
    function _revertIfHealthFactorIsBroken(address user) internal {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert TokenizedDepositEngine__UserHealthFactorIsBroken();
    }

    /**
     * @notice To get health factor of user
     * @param user The adddress to check the health factor
     */
    function _healthFactor(address user) internal returns (uint256) {}

    /**
     * @notice Helper function of _healthFactor()
     */
    function _calculateHealthFactor(address user) internal pure {}

    /////////////
    // GETTERS //
    /////////////
    /**
     * @notice Gets total amount of collateral user has desposited
     */
    function getCollateralAmountDeposited(address user) external view returns (uint256) {
        return s_collateralDeposited[user];
    }

    /**
     * @notice Gets yield interest rate
     */
    function getYieldInterestRate() external pure returns (uint256) {
        return INTEREST_RATE;
    }
}
