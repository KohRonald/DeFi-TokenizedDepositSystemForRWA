// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {RWAPriceConvertor} from "src/library/RWAPriceConvertor.sol";
import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {
    AggregatorV3Interface
} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
contract RWAToken is ERC20Burnable, Ownable {
    using RWAPriceConvertor for uint256;

    ///////////
    // ERROR //
    ///////////
    error RWAToken__AmountMustBeMoreThanZero();
    error RWAToken__BurnAmountExceedsBalance();
    error RWAToken__ETHTransferFailed();
    error RWAToken__InsufficientETHAmount();
    error RWAToken__AddressZeroRestrictedFromMinting();
    error RWAToken__TokenTooSmallToMint();

    /////////////////////
    // STATE VARIABLES //
    /////////////////////
    uint256 private constant MINTING_FEE_BPS = 50; // 0.5% = 50 basis points (adjustable)
    uint256 private constant BASIS_POINTS = 10000;

    AggregatorV3Interface private s_ETHUSDPriceFeed;
    AggregatorV3Interface private s_AssetUSDPriceFeed;

    constructor(address ethUsdPriceFeedAddress, address assetUsdPriceFeedAddress)
        ERC20("GoldToken", "Gold")
        Ownable(msg.sender)
    {
        s_ETHUSDPriceFeed = AggregatorV3Interface(ethUsdPriceFeedAddress);
        s_AssetUSDPriceFeed = AggregatorV3Interface(assetUsdPriceFeedAddress);
    }

    ////////////
    // EVENTS //
    ////////////

    event RWAToken__MintedRWATokens(address indexed to, uint256 ethAmount, uint256 fee, uint256 tokensMinted);

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
     * @notice Mints RWA tokens based on sent ETH, current prices, and 1/10 denomination
     * @dev 1 full unit of asset (e.g. 1 oz gold) → 10 tokens
     *      So 1 token ≈ 1/10th of current asset price (e.g. gold $10 → 1 token ≈ $1)
     */
    function mint() public payable {
        // 1. Checks
        if (msg.value == 0) revert RWAToken__InsufficientETHAmount();

        uint256 ethUsdValue = RWAPriceConvertor.getPrice(s_ETHUSDPriceFeed); //ethUsdValue in 1e18
        uint256 rwaUsdValue = RWAPriceConvertor.getPrice(s_AssetUSDPriceFeed); //rwaUsdValue in 1e18

        // Apply fee
        uint256 sentEthUsdValue = (msg.value * ethUsdValue) / 1e18; //sentEthUsdValue in 1e18
        uint256 fee = (sentEthUsdValue * MINTING_FEE_BPS) / BASIS_POINTS;
        uint256 actualUsdValue = ethUsdValue - fee;

        // Calculate fractional asset units (with 8 decimals precision)
        // actualUsdValue (18 dec) * 1e8 / rwaUsdValue (18 dec) → 8-decimal fractional units
        // We want 8 dec as it matches the natural precision level of Chainlink Oracle return value
        uint256 assetFractional8dec = (actualUsdValue * 1e8) / rwaUsdValue;

        // Scale to tokens: ×10 for 1/10 denomination + ×1e10 to reach 18 decimals
        uint256 tokensToMint = assetFractional8dec * 10 * 1e10;

        if (tokensToMint == 0) revert RWAToken__TokenTooSmallToMint();

        // 2. Interactions/Effects
        _mint(msg.sender, tokensToMint);
        emit RWAToken__MintedRWATokens(msg.sender, actualUsdValue, fee, tokensToMint);
    }

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
}
