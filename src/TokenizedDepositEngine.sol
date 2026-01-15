// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RWAToken} from "src/RWAToken.sol";
import {RWAShareToken} from "src/RWAShareToken.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

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
contract TokenizedDepositEngine is ReentrancyGuard, Ownable {
    ///////////
    // ERROR //
    ///////////
    error TokenizedDepositEngine__InterestRateCannotExceed10000bps();
    error TokenizedDepositEngine__RWATokenAddressCannotBeAddressZero();
    error TokenizedDepositEngine__DepositAmountMustBeMoreThanZero();
    error TokenizedDepositEngine__TransferFailed();
    error TokenizedDepositEngine__FailedToMintRWAShareToken();
    error TokenizedDepositEngine__UserHealthFactorIsBroken();

    /////////////////////
    // STATE VARIABLES //
    /////////////////////
    uint256 private s_interestRate;
    uint256 private constant INTEREST_RATE_BASIS_POINTS_FACTOR = 1e14;
    uint256 private constant INTEREST_RATE_PRECISION = 1e18;
    uint256 SECONDS_PER_YEAR = 365 days; // ≈ 31_536_000 seconds - automatically convert to seconds at compile time
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; //To adjust to appropriate health factor

    mapping(address => uint256) private s_collateralDeposited;
    mapping(address => YieldSnapshot) private s_userYieldSnapshots;
    mapping(address => uint256) private s_userTotalYieldGained;
    mapping(address => uint256) private s_rwaTokenMinted;

    RWAToken private immutable i_rwaToken;
    RWAShareToken private immutable i_rwaShareToken;

    /////////////
    // STRUCTS //
    /////////////
    struct YieldSnapshot {
        uint256 timestamp; // When this snapshot was taken
        uint256 interestRate; // Interest rate at that time (scaled)
        uint256 balance; // Collateral balance at that time
    }

    /**
     * @notice The current interest rate, stored scaled up by 1e18 for precision.
     * @dev Example: 5% is stored as 5e16 (0.05 × 1e18).
     *
     *  Interest Rate Calculation:
     *      1 basis point = 0.01%
     *      Assuming _initialInterestRateInBps = 100
     *      s_interestRate = 100 * 1e14 = 10,000,000,000,000,000 or 1e16
     *
     *      Effective Rate: s_interestRate / INTEREST_RATE_PRECISION = 1e16/1e18 = 1e^-2 = 0.01 = 1%
     *      Etc. 100 -> 1%, 500 -> 5%, 750 -> 7.5%
     */
    constructor(address rwaTokenAddress, address rwaShareTokenAddress, uint256 _initialInterestRateInBps)
        Ownable(msg.sender)
    {
        i_rwaToken = RWAToken(rwaTokenAddress); //Collateral Token
        i_rwaShareToken = RWAShareToken(rwaShareTokenAddress); //Yield Bearing Token
        s_interestRate = _initialInterestRateInBps * INTEREST_RATE_BASIS_POINTS_FACTOR;

        // Safety: max 100% = 10,000 bps
        if (_initialInterestRateInBps > 10000) revert TokenizedDepositEngine__InterestRateCannotExceed10000bps();
    }

    ////////////
    // EVENTS //
    ////////////
    event RWAShareToken__CollateralDeposited(address indexed from, uint256 amountDeposited);
    event RWAShareToken__InterestRateUpdated(uint256 bpsInput, uint256 storedRate);

    //////////////////////
    // PUBLIC FUNCTIONS //
    //////////////////////

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
    function liquidate(address userToLiquidate) public {}

    ////////////////////////
    // INTERNAL FUNCTIONS //
    ////////////////////////
    /**
     * @notice Deposits RWAToken collateral, accrues pending yield using the previous snapshot rate,
     *         adds the new deposit amount, and updates the user's yield snapshot for future periods.
     * @dev Accrues yield on the balance that existed before this deposit using the locked-in rate
     *      from the last interaction. The new deposit only starts earning from this timestamp onward.
     *      Overwrites the user's snapshot with the current rate, timestamp, and updated total balance.
     * @param _rwaTokenAddress Address of the RWAToken contract
     * @param _rwaTokensDeposited Amount of RWAToken to deposit (must be > 0)
     * @dev Reverts if transfer fails or inputs are invalid
     */
    function _depositRwaToken(address _rwaTokenAddress, uint256 _rwaTokensDeposited) internal {
        // 1. Checks
        if (_rwaTokenAddress == address(0)) revert TokenizedDepositEngine__RWATokenAddressCannotBeAddressZero();
        if (_rwaTokensDeposited == 0) revert TokenizedDepositEngine__DepositAmountMustBeMoreThanZero();

        // 2.Effects
        // Calculate and track yield gained for any prior RWAShareTokens based on last snapshot interest rate and token amounts
        // Then, tracks new deposited collateral and interest rate at that point of deposit
        _calculateYieldGained(msg.sender);
        s_collateralDeposited[msg.sender] += _rwaTokensDeposited;

        // Tracks current snapshot of: last timestamp, current interest rate, and total token amount
        // Overwrites everytime _depositRwaToken() function is called
        s_userYieldSnapshots[msg.sender] = YieldSnapshot({
            timestamp: block.timestamp, interestRate: s_interestRate, balance: s_collateralDeposited[msg.sender]
        });

        emit RWAShareToken__CollateralDeposited(msg.sender, _rwaTokensDeposited);

        // 3.Interactions
        (bool success) = IERC20(i_rwaToken).transferFrom(msg.sender, address(this), _rwaTokensDeposited);
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
     * @notice Calculates and accrues the yield gained since the last checkpoint using the locked-in interest rate from that period.
     * @dev Uses the **snapshotted interest rate** and **balance** from the previous checkpoint.
     *      This ensures that yield for past periods is calculated with the rate active at the time the period began.
     * @dev After accrual, the checkpoint timestamp is reset and the snapshot is updated to the current rate/balance for future periods.
     * @dev Yield is added to s_userTotalYieldGained[user] and is persistent across interactions.
     * @dev Yield calculation check scenario:
     *
     * Yield calculation scenario (example with multiple deposits):
     *
     * - Monday: User deposits 10 RWAShareToken
     *   → Snapshot created: rate = current rate (e.g. 5%), balance = 10, timestamp = Monday
     *
     * - Wednesday: User deposits another 10 RWAShareToken
     *   → Accrues yield on the previous 10 tokens from Monday → Wednesday using the **locked-in 5% rate**
     *   → Adds accrued yield to s_userTotalYieldGained[user]
     *   → Updates snapshot: rate = current rate (still 5%), balance = 20, timestamp = Wednesday
     *
     * - Friday: User deposits another 10 RWAShareToken
     *   → Accrues yield on the previous 20 tokens from Wednesday → Friday using the **locked-in 5% rate**
     *   → Adds to total yield
     *   → Updates snapshot: rate = current rate (still 5%), balance = 30, timestamp = Friday
     *
     * - Sunday: User withdraws all 30 RWAShareToken
     *   → Accrues yield on the previous 30 tokens from Friday → Sunday using the **locked-in 5% rate**
     *   → Adds final yield to s_userTotalYieldGained[user]
     *
     * @dev If the interest rate changes (e.g. to 10% on Thursday), the change only affects periods **after** the next user interaction.
     *      Past periods always use the rate that was snapshotted at the start of that period.
     */
    function _calculateYieldGained(address user) internal {
        YieldSnapshot memory userSnapshot = s_userYieldSnapshots[user];
        uint256 snapshotInterestRate = userSnapshot.interestRate;
        uint256 snapshotBalance = userSnapshot.balance;
        uint256 snapshotTimestamp = userSnapshot.timestamp;

        if (snapshotTimestamp == 0) {
            return; // User has not deposited before
        }

        uint256 timeElapsedSinceLastDeposit = block.timestamp - snapshotTimestamp;
        if (timeElapsedSinceLastDeposit == 0) return; // No time pass since last deposit

        // Formula: (principle amount) + (principle amount * interest rate * time)
        uint256 perSecondRate = snapshotInterestRate / SECONDS_PER_YEAR;
        uint256 newYield = (snapshotBalance * perSecondRate * timeElapsedSinceLastDeposit) / INTEREST_RATE_PRECISION;

        s_userTotalYieldGained[user] += newYield; // Add to existing interestYieldEarned
    }

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

    ////////////////////////
    // EXTERNAL FUNCTIONS //
    ////////////////////////
    /**
     * @notice Sets new interest rate for yield calculation
     */
    function setInterestRate(uint256 _newRateBps) external onlyOwner {
        if (_newRateBps > 10000) revert TokenizedDepositEngine__InterestRateCannotExceed10000bps();

        s_interestRate = _newRateBps * INTEREST_RATE_BASIS_POINTS_FACTOR;
        emit RWAShareToken__InterestRateUpdated(_newRateBps, s_interestRate);
    }

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
    function getYieldInterestRate() external view returns (uint256) {
        return s_interestRate / INTEREST_RATE_PRECISION;
    }
}
