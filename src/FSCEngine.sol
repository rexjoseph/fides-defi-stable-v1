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

    /////////////
    // State Variables //
    /////////////
    mapping(address token => address priceFeed) private s_priceFeeds; // maps token address to token price feed
    mapping(address user => mapping(address => uint256 amount)) private s_collateralDeposited; // tracks how much collateral each user has deposited essentially mapping to a mapping. map users balances to mapping of token address to amount.

    /////////////
    // State Variables //
    /////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    FidesStableCoin private immutable s_fsc;

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

    function mintFsc() external {}

    function burnFsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
