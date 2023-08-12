// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

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

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/*
    * @title FidesStableCoin
    * @author Rex Joseph
    * Collateral: Exogenous (ETH & BTC)
    * Minting: Algorithmic
    * Relative Stability: Pegged to USD
    * 
    * Contract meant to be governed by FSCEngine. Just the ERC20 implementation of our stablecoin system.
    * 
   */
contract FidesStableCoin is ERC20Burnable {
  constructor()ERC20("Fides Stable Coin", "FSC") {

  }
}