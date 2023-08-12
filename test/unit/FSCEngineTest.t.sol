// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;
import {Test} from "forge-std/Test.sol";
import {DeployFSC} from "../../script/DeployFSC.s.sol";
import {FidesStableCoin} from "../../src/FidesStableCoin.sol";
import {FSCEngine} from "../../src/FSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract FSCEngineTest is Test {
  DeployFSC deployer;
  FidesStableCoin fsc;
  FSCEngine fsce;
  HelperConfig config;
  address ethUsdPriceFeed;
  address weth;

  address public USER = makeAddr("user");
  uint256 public constant AMOUNT_COLLATERAL = 10 ether;
  uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

  // deploy
  function setUp() public {
    deployer = new DeployFSC();
    (fsc, fsce, config) = deployer.run();
    (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
    ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
  }

  /////////////
  // Price tests //
  /////////////

  function testGetUsdValue() public {
    uint256 ethAmount = 15e18;
    uint256 expectedUsd = 30000e18;
    uint256 actualUsd = fsce.getUsdValue(weth, ethAmount);
    assertEq(expectedUsd, actualUsd);
  }

  /////////////
  // depositCollateral tests //
  /////////////
  function testRevertsIfCollateralZero() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(fsce), AMOUNT_COLLATERAL);

    vm.expectRevert(FSCEngine.FSCEngine__NeedsMoreThanZero.selector);
    fsce.depositCollateral(weth, 0);
    vm.stopPrank();
  } 
}