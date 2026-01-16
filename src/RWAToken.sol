// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {RWAPriceConvertor} from "src/library/RWAPriceConvertor.sol";
import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {
    AggregatorV3Interface
} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RWAToken
 * @author Ronald Koh
 * @notice This contract is the ERC20 representation of the underlying asset
 * @notice RWAToken acts as the "base asset"
 * @notice Minting and Burning of RWAToken is handled here, ETH is stored in this contract
 *
 * Users mints RWAToken with ETH, and ETH is stored in the contract
 * Everytime a user mints RWAToken, they will be charge a fee
 * This fee is used to cover the possible appreciation of the underlying asset
 *
 * On withdrawl, the user will exchange their RWA token for ETH
 * The withdrawl value will be based on the price of the underlying asset at that point in time
 * If the price of the underlying asset increases, contract has to ensure that there is enough ETH for payout
 * The fee is used to cover the asset appreciation
 *
 * @notice We assume that the appreciation of the asset does not go beyond the fee accumulated.
 */
contract RWAToken is ERC20Burnable, Ownable, ReentrancyGuard {
    ///////////
    // ERROR //
    ///////////
    error RWAToken__AmountMustBeMoreThanZero();
    error RWAToken__BurnAmountExceedsBalance();
    error RWAToken__ETHTransferFailed();
    error RWAToken__InsufficientETHAmount();
    error RWAToken__AddressZeroRestrictedFromMinting();
    error RWAToken__TokenAmountTooSmallToMint();
    error RWAToken__TokenRedemptionTooSmall();
    error RWAToken__InsufficientEthLiquidityInContract();
    error RWAToken__StalePriceFeedData();
    error RWAToken__InvalidOraclePrice();

    /////////////////////
    // STATE VARIABLES //
    /////////////////////
    uint256 private constant MINTING_FEE_BPS = 500; // 0.05%
    uint256 private constant BASIS_POINTS = 10000;

    AggregatorV3Interface private s_ETHUSDPriceFeed;
    AggregatorV3Interface private s_AssetUSDPriceFeed;

    constructor(string memory tokenName, address ethUsdPriceFeedAddress, address assetUsdPriceFeedAddress)
        ERC20(string.concat(tokenName, "Token"), tokenName)
        Ownable(msg.sender)
    {
        s_ETHUSDPriceFeed = AggregatorV3Interface(ethUsdPriceFeedAddress);
        s_AssetUSDPriceFeed = AggregatorV3Interface(assetUsdPriceFeedAddress);
    }

    ////////////
    // EVENTS //
    ////////////
    event RWAToken__MintedRWATokens(address indexed to, uint256 ethAmount, uint256 fee, uint256 tokensMinted);
    event RWAToken__BurnedAndRedeemed(address indexed from, uint256 tokensBurned, uint256 ethSent);

    //////////////////////
    // PUBLIC FUNCTIONS //
    //////////////////////
    /**
     * @notice This functions burns token after performing validations
     * @param _amount Amount of tokens to burn
     */
    function burn(uint256 _amount) public override {
        uint256 ethToSend;

        // 1. Checks
        if (_amount == 0) revert RWAToken__AmountMustBeMoreThanZero();
        if (balanceOf(msg.sender) < _amount) revert RWAToken__BurnAmountExceedsBalance();

        (ethToSend) = calculateEthValueOfTokensToBurn(_amount);

        if (ethToSend == 0) revert RWAToken__TokenRedemptionTooSmall();
        if (address(this).balance < ethToSend) revert RWAToken__InsufficientEthLiquidityInContract();

        // 2. Effect
        super._burn(msg.sender, _amount);
        emit RWAToken__BurnedAndRedeemed(msg.sender, _amount, ethToSend);

        // 3. Interactions
        (bool success,) = address(msg.sender).call{value: ethToSend}("");
        if (!success) revert RWAToken__ETHTransferFailed();
    }

    /**
     * @notice Mints RWA tokens based on sent ETH, current prices, and 1/10 denomination
     * @dev 1 full unit of asset (e.g. 1 oz gold) → 10 tokens
     *      So 1 token ≈ 1/10th of current asset price (e.g. gold $10 → 1 token ≈ $1)
     */
    function mint() public payable {
        uint256 fee;
        uint256 usdValueMintedAfterFee;
        uint256 tokensToMint;

        // 1. Checks
        if (msg.value == 0) revert RWAToken__InsufficientETHAmount();
        (fee, usdValueMintedAfterFee, tokensToMint) = calculateTokensToMint();
        if (tokensToMint == 0) revert RWAToken__TokenAmountTooSmallToMint();

        // 2. Interactions/Effects
        _mint(msg.sender, tokensToMint);
        emit RWAToken__MintedRWATokens(msg.sender, usdValueMintedAfterFee, fee, tokensToMint);
    }

    ////////////////////////
    // INTERNAL FUNCTIONS //
    ////////////////////////
    /**
     * @notice Calculates tokens to mint and returns the fee, actual USD value minted, and tokens to mint
     */
    function calculateTokensToMint()
        internal
        returns (uint256 fee, uint256 usdValueMintedAfterFee, uint256 tokensToMint)
    {
        uint256 ethUsdValueIn1e18;
        uint256 rwaUsdValueIn1e18;

        (ethUsdValueIn1e18, rwaUsdValueIn1e18) = getPriceFeedsPrices();

        // Apply fee
        uint256 sentEthUsdValue = (msg.value * ethUsdValueIn1e18) / 1e18; //sentEthUsdValue in 1e18
        fee = (sentEthUsdValue * MINTING_FEE_BPS) / BASIS_POINTS;
        usdValueMintedAfterFee = ethUsdValueIn1e18 - fee;

        // Calculate fractional asset units (with 8 decimals precision)
        // actualUsdValue (18 dec) * 1e8 / rwaUsdValue (18 dec) → 8-decimal fractional units
        // We want 8 dec as it matches the natural precision level of Chainlink Oracle return value
        uint256 assetFractional8dec = (usdValueMintedAfterFee * 1e8) / rwaUsdValueIn1e18;

        // Scale to tokens: ×10 for 1/10 denomination + ×1e10 to reach 18 decimals
        tokensToMint = assetFractional8dec * 10 * 1e10;

        return (fee, usdValueMintedAfterFee, tokensToMint);
    }

    /**
     * @notice Calculates ETH values of tokens being burned, returns amount of ETH to send
     */
    function calculateEthValueOfTokensToBurn(uint256 _amount) internal view returns (uint256 ethToSend) {
        uint256 ethUsdValueIn1e18;
        uint256 rwaUsdValueIn1e18;

        // Calculate how much asset is that token to burn worth
        (ethUsdValueIn1e18, rwaUsdValueIn1e18) = getPriceFeedsPrices();

        // Calculate USD value of burned tokens (18 decimals)
        // Since 1 full asset unit (e.g. 1 oz) = 10 tokens → value per token = assetUsd18 / 10
        uint256 valuePerTokenIn1e18 = rwaUsdValueIn1e18 / 10;
        uint256 totalUsdValueIn1e18 = _amount * valuePerTokenIn1e18 / 1e18; // adjust for 18-dec token

        // 3. Convert to ETH amount (wei)
        // ETH amount = total USD value / ETH price (both 18 dec)
        ethToSend = (totalUsdValueIn1e18 * 1e18) / ethUsdValueIn1e18;
    }

    /**
     * @notice Gets prices of ETH/USD and RWA/USD, checks for stale price feeds, revert if prices are stale
     */
    function getPriceFeedsPrices() internal view returns (uint256 ethUsdValue, uint256 rwaUsdValue) {
        uint256 updatedAtETHUSD;
        uint256 updatedAtAssetUSD;

        (ethUsdValue, updatedAtETHUSD) = RWAPriceConvertor.getPrice(s_ETHUSDPriceFeed); //ethUsdValue in 1e18
        (rwaUsdValue, updatedAtAssetUSD) = RWAPriceConvertor.getPrice(s_AssetUSDPriceFeed); //rwaUsdValue in 1e18

        if (ethUsdValue <= 0) revert RWAToken__InvalidOraclePrice();
        if (rwaUsdValue <= 0) revert RWAToken__InvalidOraclePrice();
        if (block.timestamp - updatedAtETHUSD > 86400) revert RWAToken__StalePriceFeedData(); // 1 day max age
        if (block.timestamp - updatedAtAssetUSD > 86400) revert RWAToken__StalePriceFeedData(); // 1 day max age

        return (ethUsdValue, rwaUsdValue);
    }

    /////////////
    // GETTERS //
    /////////////
    /**
     * @notice Gets feed version of ETH/USD
     * @return The version of the price feed
     */
    function getEthUsdPriceFeedVersion() public view returns (uint256) {
        return s_ETHUSDPriceFeed.version();
    }

    /**
     * @notice Gets feed version of the asset
     * @return The version of the price feed
     */
    function getAssetUsdPriceFeedVersion() public view returns (uint256) {
        return s_AssetUSDPriceFeed.version();
    }

    /**
     * @notice Gets minting Fee
     */
    function getMintingFee() public pure returns (uint256) {
        return MINTING_FEE_BPS / BASIS_POINTS;
    }
}
