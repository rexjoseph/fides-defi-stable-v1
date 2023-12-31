// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {FidesStableCoin} from "../src/FidesStableCoin.sol";
import {FSCEngine} from "../src/FSCEngine.sol";

contract DeployFSC is Script {
  address[] public tokenAddresses;
  address[] public priceFeedAddresses;

  function run() external returns (FidesStableCoin, FSCEngine, HelperConfig) {
    HelperConfig helperConfig = new HelperConfig();

    (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) = helperConfig.activeNetworkConfig();

    tokenAddresses = [weth, wbtc];
    priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

    vm.startBroadcast(deployerKey);
    FidesStableCoin fsc = new FidesStableCoin();
    FSCEngine fscEngine = new FSCEngine(tokenAddresses, priceFeedAddresses, address(fsc));
    
    fsc.transferOwnership(address(fscEngine));
    vm.stopBroadcast();
    return (fsc, fscEngine, helperConfig);
  }
}