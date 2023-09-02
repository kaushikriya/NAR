//SPDX-License-Identifier:MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NARStablecoin} from "./NARStablecoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

pragma solidity ^0.8.13;

contract NARStablecoinEngine is ReentrancyGuard {
    error NAR_tokenAndPriceFeedLengthShouldBeSame();
    error NAR_mustBeMoreThanZero();
    error NAR_tokenIsNotAllowed();
    error NAR_transferFailed();
    error NAR_breaksHealthFactor(uint256);
    error NAR_mintFailed();

    mapping(address token => address priceFeed) s_tokenToPriceFeed;

    mapping(address user => mapping(address token => uint256 amount)) s_userToDepositedCollateral;

    mapping(address user => uint256 amount) s_mintedNAR;

    address[] s_tokens;

    uint256 immutable i_collateralThreshold = 60;

    NARStablecoin private immutable i_NAR;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    modifier tokenIsAllowed(address token) {
        if (s_tokenToPriceFeed[token] == address(0)) {
            revert NAR_tokenIsNotAllowed();
        }
        _;
    }

    modifier isMoreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert NAR_mustBeMoreThanZero();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address NARStablecoinAddress) {
        i_NAR = NARStablecoin(NARStablecoinAddress);
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert NAR_tokenAndPriceFeedLengthShouldBeSame();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_tokenToPriceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_tokens.push(tokenAddresses[i]);
        }
    }

    function depositCollateralAndMintNAR() external {}

    function depositCollateral(address tokenAddress, uint256 amount)
        public
        tokenIsAllowed(tokenAddress)
        isMoreThanZero(amount)
        nonReentrant
    {
        s_userToDepositedCollateral[msg.sender][tokenAddress] += amount;
        emit CollateralDeposited(msg.sender, tokenAddress, amount);
        bool success = IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert NAR_transferFailed();
        }
    }

    function mintNAR(uint256 amount) external nonReentrant isMoreThanZero(amount) {
        s_mintedNAR[msg.sender] += amount;
        checkAndApproveHealthFactor(msg.sender);
        bool success = i_NAR.mint(msg.sender, amount);
        if (!success) {
            revert NAR_mintFailed();
        }
    }

    function redeemCollateral() external {}

    function redeemCollateralForNAR() external {}

    function liquidate() external {}

    function getHealthFactor(address user, uint256 userCollateral) internal view returns (uint256) {
        uint256 mintedNAR = s_mintedNAR[user];
        uint256 collateralAdjustedForThreshold = userCollateral * i_collateralThreshold / 100;
        return collateralAdjustedForThreshold * 1e18 / mintedNAR;
    }

    function checkAndApproveHealthFactor(address user) internal view {
        uint256 userCollateralInUSD = getUserCollateralInformation(user);
        uint256 healthFactor = getHealthFactor(user, userCollateralInUSD);
        if (healthFactor <= 1) {
            revert NAR_breaksHealthFactor(healthFactor);
        }
    }

    function getUserCollateralInformation(address user) internal view returns (uint256 totalBalanceInUSD) {
        for (uint256 i = 0; i < s_tokens.length; i++) {
            address tokenAddress = s_tokens[i];
            uint256 balance = s_userToDepositedCollateral[user][tokenAddress];
            totalBalanceInUSD += getBalanceInUSD(balance, s_tokenToPriceFeed[tokenAddress]);
        }
        return totalBalanceInUSD;
    }

    function getBalanceInUSD(uint256 amount, address pricefeed) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(pricefeed);
        (, int256 answer,,,) = priceFeed.latestRoundData();
        return ((uint256(answer) * 1e10) * amount) / 1e18;
    }
}
