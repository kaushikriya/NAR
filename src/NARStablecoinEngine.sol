//SPDX-License-Identifier:MIT

pragma solidity ^0.8.13;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NARStablecoin} from "./NARStablecoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title NARStablecoinEngine
 * @author Riya Kaushik
 *
 * This is a very minimal implementation of a stablecoin pegged to USD and backed by WETH and WBTC. 
 *
 * @notice This handles all the logic for handling collateral i.e deposit, withdrawal as well as minting
 * and burning NAR.
 */
contract NARStablecoinEngine is ReentrancyGuard {
    // errors

    error NAR_tokenAndPriceFeedLengthShouldBeSame();
    error NAR_mustBeMoreThanZero();
    error NAR_tokenIsNotAllowed();
    error NAR_transferFailed();
    error NAR_breaksHealthFactor(uint256);
    error NAR_mintFailed();
    error NAR_healthFactorIsValid(address user, uint256 healthFactor);
    error NAR_userEndingHealthFactorBroken(address user, uint256 healthFactor);

    // Stablecoin contract
    NARStablecoin private immutable i_NAR;

    // storage and state variables

    /// @dev Mapping of token address to price feed address
    mapping(address token => address priceFeed) s_tokenToPriceFeed;
    /// @dev Mapping of user to a mapping of token and amount deposited as collateral
    mapping(address user => mapping(address token => uint256 amount)) s_userToDepositedCollateral;
    /// @dev Mapping of user to amount of minted NAR for the user
    mapping(address user => uint256 amount) s_mintedNAR;
    /// @dev Array of tokens used for collateral
    address[] s_tokens;

    uint256 constant LIQUIDATION_THRESHOLD = 60;
    uint256 constant MIN_HEALTH_FACTOR = 60;
    uint256 constant LIQUIDATION_BONUS = 10;

    // events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);
    event UserLiquidated(address indexed user, uint256 amount);

    // modifiers
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

    // Public and External functions

    /*
     * @param token: The ERC20 token address of the collateral you're depositing
     * @param amount: The amount of collateral you're depositing
     * @param amountToMint: The amount of NAR you want to mint
     * @notice This function will deposit your collateral and mint NAR in one transaction
     */
    function depositCollateralAndMintNAR(address token, uint256 amount, uint256 amountToMint) external {
        depositCollateral(token, amount);
        mintNAR(amountToMint);
    }

    /*
    @param tokenAddress: The ERC20 token address of the collateral
    @param amount: Amount of token you are depositing for collateral
    @notice This function will only deposit your collateral 
    */
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

    /*
    @param amount: The amount of NAR user wants to mint
    @notice This function will mint the given amount of NAR to the sender
    */
    function mintNAR(uint256 amount) public nonReentrant isMoreThanZero(amount) {
        _mintNAR(amount, msg.sender);
    }

    /*
    @param token: Address of the ERC20 token in which collateral has to be redeemed
    @param amount: Amount of collateral to redeem
    @notice this function will withdraw collateral in the specified token
     */
    function redeemCollateral(address token, uint256 amount)
        public
        isMoreThanZero(amount)
        tokenIsAllowed(token)
        nonReentrant
    {
        _redeemCollateral(amount, token, msg.sender, msg.sender);
        checkHealthFactorIsBroken(msg.sender);
    }

    /*
    @param token: Address of the ERC20 token in which collateral has to be redeemed
    @param amount: Amount of collateral to redeem
    @notice this function will withdraw collateral in the specified token and burn the NAR token
     */
    function redeemCollateralForNAR(address token, uint256 amount) public {
        _burnNAR(amount, msg.sender);
        _redeemCollateral(amount, token, msg.sender, msg.sender);
        checkHealthFactorIsBroken(msg.sender);
    }

    /*
    @param amount: Amount of NAR token to be burned
    @notice This function will burn the specified amount of NAR token for the user
     */
    function burnNAR(uint256 amount) public {
        _burnNAR(amount, msg.sender);
        checkHealthFactorIsBroken(msg.sender);
    }

    /*
    @param user: Address of the user being liquidated
    @param amount: Amount of USD proposed by the liquidator
    @param token: Address of ERC20 token being liquidated
    @notice This function liquidates the user for the specified amount and token. The
    user can be partially liquidated if it improves the user's health factor to be valid.
     */
    function liquidate(address user, uint256 amount, address token) public {
        uint256 startingHealthFactor = _getHealthFactor(user);
        if (startingHealthFactor > MIN_HEALTH_FACTOR) {
            revert NAR_healthFactorIsValid(user, startingHealthFactor);
        }
        uint256 debtTokenToBeRecovered = _getTokenAmountFromUSD(amount, token);
        uint256 liquidationBonus = (debtTokenToBeRecovered * LIQUIDATION_BONUS) / 100;
        _redeemCollateral(debtTokenToBeRecovered + liquidationBonus, token, user, msg.sender);
        _burnNAR(amount, user);
        uint256 endingHealthFactor = _getHealthFactor(user);
        emit UserLiquidated(user, amount);
        if (endingHealthFactor <= startingHealthFactor) {
            revert NAR_userEndingHealthFactorBroken(user, endingHealthFactor);
        }
        checkHealthFactorIsBroken(msg.sender);
    }

    // internal and private functions

    function checkHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _getHealthFactor(user);
        if (healthFactor <= 1) {
            revert NAR_breaksHealthFactor(healthFactor);
        }
    }

    function _getHealthFactor(address user) private view returns (uint256) {
        uint256 mintedNAR = s_mintedNAR[user];
        uint256 userCollateral = _getUserCollateralInformation(user);
        uint256 collateralAdjustedForThreshold = userCollateral * LIQUIDATION_THRESHOLD / 100;
        return collateralAdjustedForThreshold * 1e18 / mintedNAR;
    }

    function _getUserCollateralInformation(address user) private view returns (uint256 totalBalanceInUSD) {
        for (uint256 i = 0; i < s_tokens.length; i++) {
            address tokenAddress = s_tokens[i];
            uint256 balance = s_userToDepositedCollateral[user][tokenAddress];
            totalBalanceInUSD += _getAmountInUSD(balance, tokenAddress);
        }
        return totalBalanceInUSD;
    }

    function _getAmountInUSD(uint256 amount, address token) private view returns (uint256) {
        address priceFeedAddress = s_tokenToPriceFeed[token];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 answer,,,) = priceFeed.latestRoundData();
        return ((uint256(answer) * 1e10) * amount) / 1e18;
    }

    function _getTokenAmountFromUSD(uint256 amount, address token) private view returns (uint256) {
        address priceFeedAddress = s_tokenToPriceFeed[token];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 answer,,,) = priceFeed.latestRoundData();
        uint256 tokenAmount = amount / uint256(answer) * 10e10;
        return tokenAmount * 10e18;
    }

    function _burnNAR(uint256 amount, address from) private {
        s_mintedNAR[from] -= amount;
        bool success = i_NAR.transferFrom(from, address(this), amount);
        if (!success) {
            revert NAR_transferFailed();
        }
        i_NAR.burn(amount);
    }

    function _mintNAR(uint256 amount, address to) private {
        s_mintedNAR[msg.sender] += amount;
        checkHealthFactorIsBroken(msg.sender);
        bool success = i_NAR.mint(msg.sender, amount);
        if (!success) {
            revert NAR_mintFailed();
        }
    }

    function _redeemCollateral(uint256 amount, address token, address to, address from) private {
        s_userToDepositedCollateral[from][token] -= amount;
        // simulating health factor before the transaction is expensive so we will not follow CEI here.
        bool success = IERC20(token).transfer(payable(to), amount);
        if (!success) {
            revert NAR_transferFailed();
        }
        emit CollateralRedeemed(to, token, amount);
        checkHealthFactorIsBroken(from);
    }

    // external view and pure functions

    function getAmountInUSD(uint256 amount, address token) external view returns (uint256) {
        return _getAmountInUSD(amount, token);
    }

    function getTokenAmountFromUSD(uint256 amount, address token) external view returns (uint256) {
        return _getTokenAmountFromUSD(amount, token);
    }

    function getAccountCollateralValue(address user) public view returns (uint256) {
        return _getUserCollateralInformation(user);
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _getHealthFactor(user);
    }

    function getNAR() external view returns (address) {
        return address(i_NAR);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_tokens;
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_tokenToPriceFeed[token];
    }
}
