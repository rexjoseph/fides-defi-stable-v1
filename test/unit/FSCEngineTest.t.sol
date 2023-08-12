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
  address btcUsdPriceFeed;
  address weth;

  address public USER = makeAddr("user");
  uint256 public constant AMOUNT_COLLATERAL = 10 ether;
  uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

  // deploy
  function setUp() public {
    deployer = new DeployFSC();
    (fsc, fsce, config) = deployer.run();
    (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
    ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
  }

  /////////////
  // Constructore tests //
  /////////////
  address[] public tokenAddresses; // some public address arrays
  address[] public priceFeedAddresses;

  function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
    tokenAddresses.push(weth);
    priceFeedAddresses.push(ethUsdPriceFeed);
    priceFeedAddresses.push(btcUsdPriceFeed);

    vm.expectRevert(FSCEngine.FSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
    new FSCEngine(tokenAddresses, priceFeedAddresses, address(fsc));
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

  function testGetTokenAmountFromUsd() public {
    uint256 usdAmount = 100 ether;
    uint256 expectedWeth = 0.05 ether;
    uint256 actualWeth = fsce.getTokenAmountFromUsd(weth, usdAmount);
    assertEq(expectedWeth, actualWeth);
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

  function testRevertsWithUnapprovedCollateral() public {
    ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
    vm.startPrank(USER);
    vm.expectRevert(FSCEngine.FSCEngine__NotAllowedToken.selector);
    fsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
    vm.stopPrank();
  }

  modifier depositCollateral() {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(fsce), AMOUNT_COLLATERAL);
    fsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();
    _;
  }

  function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
    (uint256 totalFscMinted, uint256 collateralValueInUsd) = fsce.getAccountInformation(USER);
    
    uint256 expectedTotalFscMinted = 0;
    uint256 expectedDepositAmount = fsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

    assertEq(totalFscMinted, expectedTotalFscMinted);
    assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
  }
}