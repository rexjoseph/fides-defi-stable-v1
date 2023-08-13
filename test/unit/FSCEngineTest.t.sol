// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;
import {DeployFSC} from "../../script/DeployFSC.s.sol";
import {FSCEngine} from "../../src/FSCEngine.sol";
import {FidesStableCoin} from "../../src/FidesStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtFSC} from "../mocks/MockMoreDebtFSC.sol";
import {MockFailedMintFSC} from "../mocks/MockFailedMintFSC.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract FSCEngineTest is StdCheats, Test {
  event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

  FSCEngine public fsce;
  FidesStableCoin public fsc;
  HelperConfig public helperConfig;

  address public ethUsdPriceFeed;
  address public btcUsdPriceFeed;
  address public weth;
  address public wbtc;
  uint256 public deployerKey;

  uint256 amountCollateral = 10 ether;
  uint256 amountToMint = 100 ether;
  address public user = address(1);

  uint256 public constant STARTING_USER_BALANCE = 10 ether;
  uint256 public constant MIN_HEALTH_FACTOR = 1e18;
  uint256 public constant LIQUIDATION_THRESHOLD = 50;

  // Liquidation
  address public liquidator = makeAddr("liquidator");
  uint256 public collateralToCover = 20 ether;

  // deploy
  function setUp() external {
    DeployFSC deployer = new DeployFSC();
    (fsc, fsce, helperConfig) = deployer.run();
    (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
    if (block.chainid == 31337) {
        vm.deal(user, STARTING_USER_BALANCE);
    }
    ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
    ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
  }

  /////////////
  // Constructore tests //
  /////////////
  address[] public tokenAddresses; // some public address arrays
  address[] public feedAddresses;

  function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
    tokenAddresses.push(weth);
    feedAddresses.push(ethUsdPriceFeed);
    feedAddresses.push(btcUsdPriceFeed);

    vm.expectRevert(FSCEngine.FSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
    new FSCEngine(tokenAddresses, feedAddresses, address(fsc));
  }

  /////////////
  // Price tests //
  /////////////

  function testGetTokenAmountFromUsd() public {
    // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
    uint256 expectedWeth = 0.05 ether;
    uint256 amountWeth = fsce.getTokenAmountFromUsd(weth, 100 ether);
    assertEq(amountWeth, expectedWeth);
  }

  function testGetUsdValue() public {
    uint256 ethAmount = 15e18;
    uint256 expectedUsd = 30000e18;
    uint256 usdValue = fsce.getUsdValue(weth, ethAmount);
    assertEq(usdValue, expectedUsd);
  }

  /////////////
  // depositCollateral tests //
  /////////////

  // this test needs it's own setup
  function testRevertsIfTransferFromFails() public {
      // Arrange - Setup
      address owner = msg.sender;
      vm.prank(owner);
      MockFailedTransferFrom mockFsc = new MockFailedTransferFrom();
      tokenAddresses = [address(mockFsc)];
      feedAddresses = [ethUsdPriceFeed];
      vm.prank(owner);
      FSCEngine mockFsce = new FSCEngine(
          tokenAddresses,
          feedAddresses,
          address(mockFsc)
      );
      mockFsc.mint(user, amountCollateral);

      vm.prank(owner);
      mockFsc.transferOwnership(address(mockFsce));
      // Arrange - User
      vm.startPrank(user);
      ERC20Mock(address(mockFsc)).approve(address(mockFsce), amountCollateral);
      // Act / Assert
      vm.expectRevert(FSCEngine.FSCEngine__TransferFailed.selector);
      mockFsce.depositCollateral(address(mockFsc), amountCollateral);
      vm.stopPrank();
  }

  function testRevertsIfCollateralZero() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(fsce), amountCollateral);

    vm.expectRevert(FSCEngine.FSCEngine__NeedsMoreThanZero.selector);
    fsce.depositCollateral(weth, 0);
    vm.stopPrank();
  } 

  function testRevertsWithUnapprovedCollateral() public {
    ERC20Mock randToken = new ERC20Mock("RAN", "RAN", user, 100e18);
    vm.startPrank(user);
    vm.expectRevert(abi.encodeWithSelector(FSCEngine.FSCEngine__TokenNotAllowed.selector, address(randToken)));
    fsce.depositCollateral(address(randToken), amountCollateral);
    vm.stopPrank();
  }

  modifier depositedCollateral() {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(fsce), amountCollateral);
    fsce.depositCollateral(weth, amountCollateral);
    vm.stopPrank();
    _;
  }

  function testCanDepositCollateralWithoutMinting() public depositedCollateral {
      uint256 userBalance = fsc.balanceOf(user);
      assertEq(userBalance, 0);
  }

  function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
    (uint256 totalFscMinted, uint256 collateralValueInUsd) = fsce.getAccountInformation(user);
    
    uint256 expectedDepositedAmount = fsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
    assertEq(totalFscMinted, 0);
    assertEq(expectedDepositedAmount, amountCollateral);
  }
}

/////////////
  // depositCollateral tests //
/////////////