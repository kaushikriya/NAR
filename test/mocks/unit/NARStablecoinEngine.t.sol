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

    uint256 constant STARTING_USER_BALANCE = 100 ether;

    uint256 public constant collateralAmount = 10 ether;
    address USER = makeAddr("user");
    ERC20Mock fakeToken;
    address fakeTokenAddress;

    function setUp() public {
        fakeToken = new ERC20Mock('FKE','FKE', msg.sender, 1000e18);
        fakeTokenAddress = address(fakeToken);
        NARDeployer deployer = new NARDeployer();
        (narc, narcEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        vm.deal(USER, 100 ether);
        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(narcEngine), collateralAmount);
        narcEngine.depositCollateral(weth, collateralAmount);
        vm.stopPrank();
        _;
    }

    function testEthUsdPrice() external {
        uint256 ethAmount = 10e18;
        uint256 expectedPrice = 20000e18;
        uint256 amountInUsd = narcEngine.getAmountInUSD(ethAmount, weth);
        assertEq(expectedPrice, amountInUsd);
    }

    function testDepositCollateralRevertIfZeroCollateral() external {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(narcEngine), collateralAmount);
        vm.expectRevert(NARStablecoinEngine.NAR_mustBeMoreThanZero.selector);
        narcEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDepositCollateralRevertIfTokenNotAllowed() external {
        vm.startPrank(USER);
        ERC20Mock(fakeToken).approve(address(narcEngine), collateralAmount);
        vm.expectRevert(NARStablecoinEngine.NAR_tokenIsNotAllowed.selector);
        narcEngine.depositCollateral(address(fakeToken), collateralAmount);
        vm.stopPrank();
    }

    function testReddemCollateralRevertIfZeroCollateral() external {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(narcEngine), collateralAmount);
        vm.expectRevert(NARStablecoinEngine.NAR_mustBeMoreThanZero.selector);
        narcEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testReddemCollateralRevertIfTokenNotAllowed() external {
        vm.startPrank(USER);
        ERC20Mock(fakeToken).approve(address(narcEngine), collateralAmount);
        vm.expectRevert(NARStablecoinEngine.NAR_tokenIsNotAllowed.selector);
        narcEngine.redeemCollateral(address(fakeToken), collateralAmount);
        vm.stopPrank();
    }

    function testGetTokenAmountFromUSD() external {
        uint256 usdAmount = 200e18;
        uint256 expectedAmount = 0.1 ether;
        uint256 tokenAmount = narcEngine.getTokenAmountFromUSD(usdAmount, weth);
        assertEq(expectedAmount, tokenAmount);
    }

    address[] tokens;
    address[] priceFeeds;

    function testRevertIfTokensLengthDontMatchPriceFeed() external {
        vm.startPrank(USER);
        tokens.push(weth);
        priceFeeds.push(ethUsdPriceFeed);
        priceFeeds.push(btcUsdPriceFeed);
        vm.expectRevert(NARStablecoinEngine.NAR_tokenAndPriceFeedLengthShouldBeSame.selector);
        new NARStablecoinEngine(tokens, priceFeeds, address(narc));
        vm.stopPrank();
    }

    function testDepositCollateral() external depositCollateral {
        uint256 userCollateralInUSD = narcEngine.getAccountCollateralValue(USER);
        uint256 collateralAmountInUSD = narcEngine.getAmountInUSD(collateralAmount, weth);
        assertEq(userCollateralInUSD, collateralAmountInUSD);
    }

    function testDepositCollateralWithoutMintingNAR() external depositCollateral {
        uint256 userNARBalance = narcEngine.getUserBalance(USER);
        assertEq(userNARBalance, 0);
    }

    function testMintNAR() external depositCollateral {
        vm.startPrank(USER);
        narcEngine.mintNAR(100);
        uint256 userNARBalance = narcEngine.getUserBalance(USER);
        assertEq(userNARBalance, 100);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintNAR() external {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(narcEngine), collateralAmount);
        narcEngine.depositCollateralAndMintNAR(weth, collateralAmount, 1000);
        uint256 userNARBalance = narcEngine.getUserBalance(USER);
        assertEq(userNARBalance, 1000);
    }

    function testMintRevertIfHealthFactorBreaks() external {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(NARStablecoinEngine.NAR_breaksHealthFactor.selector, 0));
        narcEngine.mintNAR(100);
        vm.stopPrank();
    }

    function testRevertRedeemCollateralwithoutEnoughCollateral() external {
        vm.startPrank(USER);
        vm.expectRevert();
        narcEngine.redeemCollateral(weth, 1 ether);
        vm.stopPrank();
    }

    function testRedeemCollateral() external depositCollateral {
        vm.startPrank(USER);
        uint256 userStartingBalanceInUSD= narcEngine.getAccountCollateralValue(USER); 
        narcEngine.redeemCollateral(weth, 1 ether);
        uint256 userEndingBalanceInUSD= narcEngine.getAccountCollateralValue(USER);
        assertEq(userStartingBalanceInUSD - userEndingBalanceInUSD, 2000e18);
    }

    function testRedeemCollateralIfHEalthFactorBreaks() external depositCollateral{}
}
