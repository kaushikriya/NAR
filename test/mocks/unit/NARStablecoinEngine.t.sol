//SPDX-License-Indetifier:MIT

pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NARStablecoin} from "../../../src/NARStablecoin.sol";
import {NARStablecoinEngine} from "../../../src/NARStablecoinEngine.sol";
import {NARDeployer} from "../../../script/NARDeployer.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzepplin/contracts/mocks/ERC20Mock.sol";

contract NARStablecoinEngineTest is Test {
    NARStablecoin narc;
    NARStablecoinEngine narcEngine;
    HelperConfig config;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 public constant collateralAmount = 10 ether;
    address USER = makeAddr("user");

    function setUp() public {
        NARDeployer deployer = new NARDeployer();
        (narc, narcEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
    }

    function testEthUsdPrice() external {
        uint256 ethAmount = 10e18;
        uint256 expectedPrice = 20000e18;
        uint256 amountInUsd = narcEngine.getBalanceInUSD(ethAmount, ethUsdPriceFeed);
        assertEq(expectedPrice, amountInUsd);
    }

    function testRevertIfZeroCollateral() external {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(narcEngine), collateralAmount);
        vm.expectRevert(NARStablecoinEngine.NAR_mustBeMoreThanZero.selector);
        narcEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
