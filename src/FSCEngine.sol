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

import {OracleLib, AggregatorV3Interface} from "./libraries/OracleLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FidesStableCoin} from "./FidesStableCoin.sol";

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
    error FSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error FSCEngine__NeedsMoreThanZero();
    error FSCEngine__TokenNotAllowed(address token);
    error FSCEngine__TransferFailed();
    error FSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error FSCEngine__MintFailed();
    error FSCEngine__HealthFactorOk();
    error FSCEngine__HealthFactorNotImproved();

    /////////////
    // Types //
    /////////////
    using OracleLib for AggregatorV3Interface;

    /////////////
    // State Variables //
    /////////////
    FidesStableCoin private immutable i_fsc;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    mapping(address collateralToken => address priceFeed) private s_priceFeeds; // maps token address to token price feed
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    /// @dev Amount of FSC minted by user // tracks how much collateral each user has deposited essentially mapping to a mapping. map users balances to mapping of token address to amount.
    // keep track how much FSC everybody has minted
    mapping(address user => uint256 amount) private s_FSCMinted;
    address[] private s_collateralTokens; // array of all collateral tokens

    /////////////
    // Events //
    /////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);


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
            revert FSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    /////////////
    // Functions //
    /////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address fscAddress) {
        // in order to get a pricing, we're using the USD price feed from Chainlink
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert FSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_fsc = FidesStableCoin(fscAddress);
    }

    /////////////
    // External Functions //
    /////////////

    /*
    * @param tokenCollateralAddress The address of the token to be deposited as collateral.
    *@param amountCollateral The amount of collateral to be deposited.
    *@param amountFscToMint The amount of FSC to be minted.
    *@notice this function deposits your collateral and mints FSC in one transaction
    */
    function depositCollateralAndMintFsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountFscToMint) external {
      depositCollateral(tokenCollateralAddress, amountCollateral);
      mintFsc(amountFscToMint);
    }

    /*
    @notice Follows CEI pattern
    @param tokenCollateralAddress The address of the token to be deposited as collateral.
    @param amountCollateral The amount of collateral to be deposited.
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral) nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert FSCEngine__TransferFailed();
        }
    }

    /*
    * @param tokenCollateralAddress The collateral address to redeem.
    * @param amountCollateral The amount of collateral to redeem.
    * @param amountFscToBurn The amount of FSC to burn.
    * This function burns FSC and redeems collateral in one transaction.
    */
    function redeemCollateralForFsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountFscToBurn) external moreThanZero(amountCollateral) {
      _burnFsc(amountFscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
      // redeemCollateral already checks health factor
    }

    // in order to redeem collateral
    // 1. health factor must be over 1 AFTEr collateral pull 
    // CEI: Check, Effects, Interactions
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) external moreThanZero(amountCollateral) nonReentrant {
     _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice Follows CEI pattern
     * @param amountFscToMint The amount of FSC to be minted.
     * @notice they must have more collateral value than the min threshold. 
     */
    // Check if the collateral value > FSC. Price feeds, etc.
    function mintFsc(uint256 amountFscToMint) public moreThanZero(amountFscToMint) nonReentrant {
      s_FSCMinted[msg.sender] += amountFscToMint;
      // if they mint too much ($150 FSC, $100 ETH), then they can't mint and should revert
      revertIfHealthFactorIsBroken(msg.sender);
      bool minted = i_fsc.mint(msg.sender, amountFscToMint);
      if (minted != true) {
        revert FSCEngine__MintFailed();
      }
    }

    function burnFsc(uint256 amount) external moreThanZero(amount) {
      _burnFsc(amount, msg.sender, msg.sender);
      revertIfHealthFactorIsBroken(msg.sender); // prolly don't need this but hypothetically it's like burning too much ($150 FSC, $100 ETH)
    }

    // if we start nearing undercollateralization, we need someone to liquidate positions
    // If someone becomes undercollateralized, we pay you to liquidate them
    /*
    * @param collateral The collateral to be liquidated.
    * @param user The user to be liquidated. Their health factor must be below MIN_HEALTH_FACTOR.
    * @param debtToCover The amount of debt to cover. Essentially the amount of FSC to burn to improve the users health factor
    * @notice You can partially liquidate a user. You don't have to liquidate all their debt.
    * @notice you will get a liquidation bonus for taking the users funds
    * @notice This function working assumes the protocl will be roughly 200% overcollateralized for this to work.
    * @notice a known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidator to liquidate the user.
    * For example, if the price of the collateral plummeted before anyone could be liquidated
    * Follows CEI: Checks, Effects & Interactions
    */
    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
      // check health factor of the user
      uint256 startingUserHealthFactor = _healthFactor(user);
      if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
        revert FSCEngine__HealthFactorOk();
      }
      // burn their FSC debt then take their collateral
      uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
      
      uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
      
      _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnFsc(debtToCover, user, msg.sender);

      uint256 endingUserHealthFactor = _healthFactor(user);

      if (endingUserHealthFactor <= startingUserHealthFactor) {
        revert FSCEngine__HealthFactorNotImproved();
      }
      revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    /////////////
    // Private & Internal View Functions //
    /////////////

    // functions with leading underscores(_) tell other developers that they are internal functions

    /*
    * @dev Low level function here and should not be called unless the function calling it is checking for health factors being broken
    */
    function _burnFsc(uint256 amountFscToBurn, address onBehalfOf, address fscFrom) private {
      s_FSCMinted[onBehalfOf] -= amountFscToBurn;
      bool success = i_fsc.transferFrom(fscFrom, address(this), amountFscToBurn);
      // hypothetically this conditional is unreachable
      if (!success) {
        revert FSCEngine__TransferFailed();
      }
      i_fsc.burn(amountFscToBurn);
    }

    function _redeemCollateral (address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
      s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
      emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

      bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
      if (!success) {
        revert FSCEngine__TransferFailed();
      }
    }

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
       return _calculateHealthFactor(totalFscMinted, collateralValueInUsd);
      // return (collateralValueInUsd / totalFscMinted);
    }

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _calculateHealthFactor(uint256 totalFscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalFscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        return (collateralAdjustedForThreshold * 1e18) / totalFscMinted;
    }

     // 1. Check health factor (do they have suffi collateral? )
      // 2. Revert if not
    function revertIfHealthFactorIsBroken(address user) internal view {
      uint256 userHealthFactor = _healthFactor(user);
     if (userHealthFactor < MIN_HEALTH_FACTOR) {
       revert FSCEngine__BreaksHealthFactor(userHealthFactor);
     }
    }

    /////////////
    // Public & Internal View Functions //
    /////////////
    function calculateHealthFactor(uint256 totalFscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalFscMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalFscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getFsc() external view returns (address) {
        return address(i_fsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

}
