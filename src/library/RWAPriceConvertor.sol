// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    AggregatorV3Interface
} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Gets the Price of the underlying asset
 * @author Ronald Koh
 * @notice ChainLink Oracle interactions
 */
library RWAPriceConvertor {
    /**
     * @notice Gets price of the asset from Chainlink Oracles
     * @param priceFeedAddress Address of the asset
     */
    function getPrice(AggregatorV3Interface priceFeedAddress) internal view returns (uint256, uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 answer,, uint256 updatedAt,) = priceFeed.latestRoundData();

        // Chainlink USD feeds have 8 decimals → normalize by multiplying by 1e10 to get 18 decimals
        // Returns last timestamp that the price feed was updated for staleness checks
        return (uint256(answer * 1e10), updatedAt);
    }

    /**
     * @notice Calculates ETH total balance in USD
     * @param totalEthBalance User ETH Balance
     * @param priceFeedAddress Price Feed Address of USD/ETH from Chainlink Oracle
     */
    function calculateTotalBalanceInUsd(uint256 totalEthBalance, AggregatorV3Interface priceFeedAddress)
        internal
        view
        returns (uint256)
    {
        (uint256 ethPrice,) = getPrice(priceFeedAddress);
        uint256 totalEthAmountInUsd = (ethPrice * totalEthBalance) / 1e18;
        return totalEthAmountInUsd;
    }
}
