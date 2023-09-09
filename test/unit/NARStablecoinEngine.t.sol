//SPDX-License-Indetifier:MIT

pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {NARStablecoin} from "../../src/NARStablecoin.sol";
import {NARStablecoinEngine} from "../../src/NARStablecoinEngine.sol";
import {NARDeployer} from "../../script/NARDeployer.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzepplin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from '../mocks/MockV3Aggregator.sol';


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

    address USER = makeAddr("user");
    ERC20Mock fakeToken;
    address fakeTokenAddress;
    address LIQUIDATOR;
    uint256 amountToMint = 5000e18; // equivalent to 6000$
    uint256 public constant collateralAmount = 10 ether;

    function setUp() public {
        fakeToken = new ERC20Mock('FKE','FKE', msg.sender, 1000e18);
        fakeTokenAddress = address(fakeToken);
        NARDeployer deployer = new NARDeployer();
        (narc, narcEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        vm.deal(USER, 100 ether);
        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
        LIQUIDATOR= makeAddr('liquidator');
        vm.deal(LIQUIDATOR, 100 ether);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_USER_BALANCE);
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(narcEngine), collateralAmount);
        narcEngine.depositCollateral(weth, collateralAmount);
        vm.stopPrank();
        _;
    }

     modifier depositAndMintNAR(address _to){
        vm.startPrank(_to);
        ERC20Mock(weth).approve(address(narcEngine), collateralAmount);
        narcEngine.depositCollateralAndMintNAR(weth, collateralAmount, amountToMint);
        vm.stopPrank();
        _;
    }

    // Price feed tests

      function testEthUsdPrice() external {
        uint256 ethAmount = 10e18;
        uint256 expectedPrice = 20000e18;
        uint256 amountInUsd = narcEngine.getAmountInUSD(ethAmount, weth);
        assertEq(expectedPrice, amountInUsd);
    }

     function testGetTokenAmountFromUSD() external {
        uint256 usdAmount = 200e18;
        uint256 expectedAmount = 0.1 ether;
        uint256 tokenAmount = narcEngine.getTokenAmountFromUSD(usdAmount, weth);
        assertEq(expectedAmount, tokenAmount);
    }

       // Tests for deposit collateral

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

       function testDepositCollateral() external depositCollateral {
        uint256 userCollateralInUSD = narcEngine.getAccountCollateralValue(USER);
        uint256 collateralAmountInUSD = narcEngine.getAmountInUSD(collateralAmount, weth);
        assertEq(userCollateralInUSD, collateralAmountInUSD);
    }

    function testDepositCollateralWithoutMintingNAR() external depositCollateral {
        uint256 userNARBalance = narcEngine.getUserBalance(USER);
        assertEq(userNARBalance, 0);
    }

    function testDepositCollateralAndMintNAR() external {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(narcEngine), collateralAmount);
        narcEngine.depositCollateralAndMintNAR(weth, collateralAmount, 1000e18);
        uint256 userNARBalance = narcEngine.getUserBalance(USER);
        assertEq(userNARBalance, 1000e18);
    }

    // Test for constructor


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

    // Tests for mintNAR

     function testMintNAR() external depositCollateral {
        vm.startPrank(USER);
        narcEngine.mintNAR(1 ether);
        uint256 userNARBalance = narcEngine.getUserBalance(USER);
        assertEq(userNARBalance, 1 ether);
        vm.stopPrank();
    }

    function testMintRevertIfHealthFactorBreaks() external depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(NARStablecoinEngine.NAR_breaksHealthFactor.selector, 8e17));
        narcEngine.mintNAR(15000e18); // we have USD 20,000 collateral
        vm.stopPrank();
    }

    function testMintRevertIfAmountIsZero() external {
         vm.startPrank(USER);
        vm.expectRevert(NARStablecoinEngine.NAR_mustBeMoreThanZero.selector);
        narcEngine.mintNAR(0);
        vm.stopPrank();
    }

    // Tests for redeem collateral

       function testReddemCollateralRevertIfZeroAmount() external {
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

    function testRevertRedeemCollateralwithoutEnoughCollateral() external {
        vm.startPrank(USER);
        vm.expectRevert();
        narcEngine.redeemCollateral(weth, 1 ether);
        vm.stopPrank();
    }

    function testRevertRedeemCollateralIfHealthFactorBreaks() external depositCollateral {
        vm.startPrank(USER);
        narcEngine.mintNAR(10000e18);
        vm.expectRevert(abi.encodeWithSelector(NARStablecoinEngine.NAR_breaksHealthFactor.selector, 6e17));
        narcEngine.redeemCollateral(weth, 5 ether);
        vm.stopPrank();
    }

     function testRedeemCollateral() external depositCollateral {
        vm.startPrank(USER);
        uint256 userStartingBalanceInUSD = narcEngine.getAccountCollateralValue(USER);
        narcEngine.redeemCollateral(weth, 1 ether);
        uint256 userEndingBalanceInUSD = narcEngine.getAccountCollateralValue(USER);
        assertEq(userStartingBalanceInUSD - userEndingBalanceInUSD, 2000e18);
    }

    function testRedeemCollateralAndBurnNAR() external depositAndMintNAR(USER) {
        vm.startPrank(USER);
        narc.approve(address(narcEngine), 2000e18);
        ERC20Mock(weth).approve(address(narcEngine), 3000e18);
        uint256 userStartingBalance= narcEngine.getUserBalance(USER);
        uint256 userStartingCollateralInUSD= narcEngine.getAccountCollateralValue(USER);
        narcEngine.redeemCollateralForNAR(weth, 2000e18, 2 ether);
        uint256 userEndingBalance= narcEngine.getUserBalance(USER);
        uint256 userEndingCollateralInUSD= narcEngine.getAccountCollateralValue(USER);
        assertEq(userStartingBalance, userEndingBalance+ 2000e18);
        assertEq(userStartingCollateralInUSD, userEndingCollateralInUSD+ 4000e18);
        vm.stopPrank();
    }

    // Tests for health factor

    function testShouldCalculateHealthFactor() external depositCollateral{
        vm.startPrank(USER);
        narcEngine.mintNAR(6000e18);
        // collateralAmountInUSD= 2000e18
        // Liquidation threshold= 60
        // adjusted collateral = (2000e18 * 60)/100
        // healthFactor= 12000e18/6000e18 i.e collateral adjusted/ total NAR minted
        uint256 expectedHealthFactor= 2e18;
        uint256 actualHealthFactor= narcEngine.getHealthFactor(USER);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function testHealthFactorBelowZero() external depositAndMintNAR(USER) {
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(500e8);
        vm.startPrank(USER);
        uint256 userHealthFactor= narcEngine.getHealthFactor(USER);
        // collateral = 10 ether
        // adjusted collateral = 6 ether
        // collateral in usd at $500/eth = 6*500 = 3000e18
        // health factor = (3000e18/5000e18) * 1e18 = 6e17
        console2.log(userHealthFactor);
        assertEq(userHealthFactor,6e17);
        vm.stopPrank();
    }


    // Tests for burn NAR

    function testBurnNAR() external depositAndMintNAR(USER) {
        uint256 tokenBurnAmount= 2 ether;
        uint256 userStartingBalance= narcEngine.getUserBalance(USER);
        vm.startPrank(USER);
        narc.approve(address(narcEngine), tokenBurnAmount); // NAR is an ERC20 and user needs to approve the transaction
        narcEngine.burnNAR(tokenBurnAmount);
        uint256 userEndingBalance= narcEngine.getUserBalance(USER);
        vm.stopPrank();
        assertEq(userStartingBalance, userEndingBalance + tokenBurnAmount);
    }

    function testBurnNARRevertIfAmountIsZero() external depositAndMintNAR(USER) {
        vm.startPrank(USER);
        narc.approve(address(narcEngine), 10 ether);
        vm.expectRevert(NARStablecoinEngine.NAR_mustBeMoreThanZero.selector);
        narcEngine.burnNAR(0);
        vm.stopPrank();
    }

     function testBurnNARRevertWithoutMintedNAR() external {
        vm.startPrank(USER);
        narc.approve(address(narcEngine), 10 ether); 
        vm.expectRevert();
        narcEngine.burnNAR(1 ether);
        vm.stopPrank();
    }

    // test for liquidation
    function testShouldNotLiquidateHealthyUser() external depositAndMintNAR(USER) {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(abi.encodeWithSelector(NARStablecoinEngine.NAR_healthFactorIsValid.selector, address(USER), 24e17));
        narcEngine.liquidate(USER, 100e18, weth);
        vm.stopPrank();
    }

     function testShouldNotLiquidateForInvalidToken() external {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(NARStablecoinEngine.NAR_tokenIsNotAllowed.selector);
        narcEngine.liquidate(USER, 100e18, fakeTokenAddress);
        vm.stopPrank();
    }

     function testShouldNotLiquidateIfAmountZero() external {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(NARStablecoinEngine.NAR_mustBeMoreThanZero.selector);
        narcEngine.liquidate(USER, 0, weth);
        vm.stopPrank();
    }

    function testShouldLiquidateUser() external depositAndMintNAR(USER) depositAndMintNAR(LIQUIDATOR) {
        vm.startPrank(LIQUIDATOR);

        // liquidator approves to burn token and weth to transfer collateral
        narc.approve(address(narcEngine), amountToMint);
        ERC20Mock(weth).approve(address(narcEngine), 50 ether);
        narcEngine.depositCollateral(weth, 50 ether);

        // prices dip
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(800e8);

        // liquidation and assertion
        uint256 userStartingHealthFactor= narcEngine.getHealthFactor(USER); //96e16
        assertEq(userStartingHealthFactor, 96e16);
        narcEngine.liquidate(USER,amountToMint,weth); // paying off the whole debt;
        uint256 userEndingHealthFactor= narcEngine.getHealthFactor(USER);
        assertEq(userEndingHealthFactor, type(uint256).max );
        uint256 userEndingCollateralValue= narcEngine.getAccountCollateralValue(USER);
        // debt paid off for 5000/800  = 6.25 ether
        // liquidation bonus for liquidator 6.25 * 0.1 = 0.625 
        // total ether deducted from collateral = 6.875
        // remaining collateral = 10 ether * 800 - 6.875 * 800 = 2500$
        assertEq( userEndingCollateralValue, 2500e18);
        vm.stopPrank();
    }

     function testShouldPartiallyLiquidateUser() external depositAndMintNAR(USER) depositAndMintNAR(LIQUIDATOR) {
        vm.startPrank(LIQUIDATOR);

        // liquidator approves to burn token and weth to transfer collateral
        narc.approve(address(narcEngine), amountToMint);
        ERC20Mock(weth).approve(address(narcEngine), 50 ether);
        narcEngine.depositCollateral(weth, 50 ether);

        // prices dip
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(800e8);

        // liquidation and assertion
        uint256 userStartingHealthFactor= narcEngine.getHealthFactor(USER); //96e16
        assertEq(userStartingHealthFactor, 96e16);
        narcEngine.liquidate(USER,1000e18,weth); // paying off the whole debt;
        uint256 userEndingHealthFactor= narcEngine.getHealthFactor(USER);
        assertEq(userEndingHealthFactor, 1035e15 );
        uint256 userEndingCollateralValue= narcEngine.getAccountCollateralValue(USER);
        // debt paid off for 1000/800  = 1.25 ether
        // liquidation bonus for liquidator 1.25 * 0.1 = 0.125 
        // total ether deducted from collateral = 1.375
        // remaining collateral = 10 ether * 800 - 6.875 * 800 = 6900$
        assertEq( userEndingCollateralValue, 6900e18);
        vm.stopPrank();
    }

     function testShouldRevertIfLiquidatorHealthFactorBroken() external depositAndMintNAR(USER) depositAndMintNAR(LIQUIDATOR) {
        vm.startPrank(LIQUIDATOR);

        // liquidator approves to burn token and weth to transfer collateral
        narc.approve(address(narcEngine), amountToMint);

        // prices dip
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(800e8);

        // liquidation and assertion
        uint256 userStartingHealthFactor= narcEngine.getHealthFactor(USER); //96e16
        assertEq(userStartingHealthFactor, 96e16);
        vm.expectRevert(abi.encodeWithSelector(NARStablecoinEngine.NAR_breaksHealthFactor.selector, 96e16));
        narcEngine.liquidate(USER,1000e18,weth); // paying off the whole debt;
        vm.stopPrank();
    }






}
