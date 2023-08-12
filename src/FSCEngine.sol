// SPDX-License-Identifier: MIT

// This is the FSC Engine. It is the contract that governs the Fides Stable Coin. It is the only contract that can mint FSC.

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

pragma solidity ^0.8.18;

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

contract FSCEngine {
  function depositCollateralAndMintFsc() external {

  }

  function redeemCollateralForFsc() external {

  }

  function burnFsc() external {

  }

  function liquidate() external {

  }

  function getHealthFactor() external view {

  }
}