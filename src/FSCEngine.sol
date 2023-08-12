// SPDX-License-Identifier: MIT

// This is the FSC Engine. It is the contract that governs the Fides Stable Coin. It is the only contract that can mint FSC.

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
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

pragma solidity ^0.8.18;

import {FidesStableCoin} from "./FidesStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
  * @title FSCEngine
  * @author Rex Joseph
  * @dev Designed to be as minimal as possible, and have the token maintain a 1 token == $1 peg.
  * Has the properties:
  * - Exogenous
  * - Dollar Pegged
  * - Algorithmically Stable
  * 
  * Quite similar to DAI if DAI had no governance, fees and only backed by WETH and WBTC.
  * 
  * FSC system should always be "overcollateralized". At no point, should the value of
  * all collateral <= the $ backed value of all FSC.
  * 
  * @notice This contract is the core of the FSC System. It handles all the logic for minting
  * and redeeming FSC, as well as depositing & withdrawing collateral.
  * 
  * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system.
  * 
*/

contract FSCEngine is ReentrancyGuard {
    /////////////
    // Errors //
    /////////////
    error FSCEngine__NeedsMoreThanZero();
    error FSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error FSCEngine__NotAllowedToken();
    error FSCEngine__TransferFailed();
    error FSCEngine__BreaksHealthFactor(uint256 healthFactor);

    /////////////
    // State Variables //
    /////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; // maps token address to token price feed
    mapping(address user => mapping(address => uint256 amount)) private s_collateralDeposited; // tracks how much collateral each user has deposited essentially mapping to a mapping. map users balances to mapping of token address to amount.
    // keep track how much FSC everybody has minted
    mapping(address user => uint256 amountFscMinted) private s_FSCMinted;
    address[] private s_collateralTokens; // array of all collateral tokens

    FidesStableCoin private immutable s_fsc;

    /////////////
    // Events //
    /////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);


    /////////////
    // Modifiers //
    /////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert FSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert FSCEngine__NotAllowedToken();
        }
        _;
    }

    /////////////
    // Functions //
    /////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address fscAddress) {
        // in order to get a pricing, we're using the USD price feed from Chainlink
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert FSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        s_fsc = FidesStableCoin(fscAddress);
    }

    /////////////
    // External Functions //
    /////////////

    function depositCollateralAndMintFsc() external {}

    /*
    @notice Follows CEI pattern
    @param tokenCollateralAddress The address of the token to be deposited as collateral.
    @param amountCollateral The amount of collateral to be deposited.
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert FSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForFsc() external {}

    function redeemCollateral() external {}

    /*
     * @notice Follows CEI pattern
     * @param amountFscToMint The amount of FSC to be minted.
     * @notice they must have more collateral value than the min threshold. 
     */
    // Check if the collateral value > FSC. Price feeds, etc.
    function mintFsc(uint256 amountFscToMint) external moreThanZero(amountFscToMint) nonReentrant {
      s_FSCMinted[msg.sender] += amountFscToMint;
      // if they mint too much ($150 DSC, $100 ETH), then they can't mint and should revert
      _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnFsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /////////////
    // Private & Internal View Functions //
    /////////////

    // functions with leading underscores(_) tell other developers that they are internal functions

   function  _getAccountInformation(address user) private view returns(uint256 totalFscMinted, uint256 collateralValueInUsd) {
      totalFscMinted = s_FSCMinted[user];
      collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns(uint256) {
      // 1. Get the total FSC minted
      // 2. Get the value of all collateral
      (uint256 totalFscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
      uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
      return (collateralAdjustedForThreshold * PRECISION) / totalFscMinted;
      // return (collateralValueInUsd / totalFscMinted);
    }

     // 1. Check health factor (do they have suffi collateral? )
      // 2. Revert if not
    function _revertIfHealthFactorIsBroken(address user) internal view {
      uint256 userHealthFactor = _healthFactor(user);
     if (userHealthFactor < MIN_HEALTH_FACTOR) {
       revert FSCEngine__BreaksHealthFactor(userHealthFactor);
     }
    }

    /////////////
    // Public & Internal View Functions //
    /////////////
    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUsd) {
      // loop through each collateral token, get the amount they have deposited, and map it to the price, to get the USD value
      for (uint256 i = 0; i < s_collateralTokens.length; i++) {
        address token = s_collateralTokens[i];
        uint256 amount = s_collateralDeposited[user][token];
        totalCollateralValueInUsd += getUsdValue(token, amount);
      }
      return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
      AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
      (,int256 price ,,,) = priceFeed.latestRoundData();
      return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
