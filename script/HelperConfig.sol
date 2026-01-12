// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Script} from "lib/forge-std/src/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

/**
 * @title Script to prepare NetworkConfig based on which chain the contract is being deployed to
 * @author Ronald Koh
 */
contract HelperConfig is Script {
    struct NetworkConfig {
        address ethUsdPriceFeed;
        address assetUsdPriceFeed;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant MOCK_ETH_USD_PRICE = 2000e8; //$2,000.00 per ETH
    int256 public constant MOCK_ASSET_USD_PRICE = 1000e8; //$1,000.00 per Asset

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    /**
     * @notice Retrieves price feed addresses and returns them as a NetworkConfig struct
     * @dev Currently asset price feed is hardcoded to GOLD, in the future to make it dynamic
     */
    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            assetUsdPriceFeed: 0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea
        });
    }

    /**
     * @notice Mocks price feed addresses and returns them as a NetworkConfig struct
     */
    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.ethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, MOCK_ETH_USD_PRICE);
        MockV3Aggregator assetUsdPriceFeed = new MockV3Aggregator(DECIMALS, MOCK_ASSET_USD_PRICE);
        vm.stopBroadcast();

        return NetworkConfig({ethUsdPriceFeed: address(ethUsdPriceFeed), assetUsdPriceFeed: address(assetUsdPriceFeed)});
    }
}
