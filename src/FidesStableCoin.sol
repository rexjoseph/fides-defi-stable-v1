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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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
contract FidesStableCoin is ERC20Burnable, Ownable {
  error FidesStableCoin__MustBeMoreThanZero();
  error FidesStableCoin__BurnAmountExceedsBalance();

  constructor()ERC20("Fides Stable Coin", "FSC") {
  }

  function burn(uint256 _amount) public override onlyOwner {
    uint256 balance = balanceOf(msg.sender);
    if (_amount <= 0) {
      revert FidesStableCoin__MustBeMoreThanZero();
    }
    if (balance < _amount) {
      revert FidesStableCoin__BurnAmountExceedsBalance();
    }
    super.burn(_amount);
  }
}