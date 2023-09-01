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
import {NARStablecoin} from './NARStablecoin.sol';

error NAR_tokenAndPriceFeedLengthShouldBeSame();

error NAR_mustBeMoreThanZero();

error NAR_tokenIsNotAllowed();

error NAR_transferFailed();

pragma solidity ^0.8.13;

contract NAREngine is ReentrancyGuard {
    mapping(address token => address priceFeed) s_tokenToPriceFeed;

    mapping(address user => mapping(address token => uint256 amount)) s_userToDepositedCollateral;

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

    function redeemCollateral() external {}

    function redeemCollateralForNAR() external {}

    function liquidate() external {}

    function getHealthFactor() external {}
}
