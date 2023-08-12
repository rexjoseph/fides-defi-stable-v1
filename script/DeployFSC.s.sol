// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {FidesStableCoin} from "../src/FidesStableCoin.sol";
import {FSCEngine} from "../src/FSCEngine.sol";

contract DeployFSC is Script {
  function run() external returns (FidesStableCoin, FSCEngine) {
    vm.startBroadcast();
    FidesStableCoin fsc = new FidesStableCoin();
    // FSCEngine engine = new FSCEngine();
    vm.stopBroadcast();
  }
}