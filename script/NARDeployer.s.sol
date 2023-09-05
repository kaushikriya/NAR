//SPDX-License-Identifier:MIT

pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {NARStablecoin} from "../src/NARStablecoin.sol";
import {NARStablecoinEngine} from "../src/NARStablecoinEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract NARDeployer is Script {
    address[] tokenAddresses;

    address[] priceFeedAddresses;

    function run() external returns (NARStablecoin, NARStablecoinEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.startBroadcast(deployerKey);
        NARStablecoin narsc = new NARStablecoin();
        NARStablecoinEngine narscEngine = new NARStablecoinEngine(tokenAddresses, priceFeedAddresses, address(narsc));
        narsc.transferOwnership(address(narscEngine));
        vm.stopBroadcast();

        return (narsc, narscEngine, config);
    }
}
