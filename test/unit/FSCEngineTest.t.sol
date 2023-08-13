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

  /////////////
  // depositCollateralAndMintFsc tests //
  /////////////

  function testRevertsIfMintedFscBreaksHealthFactor() public {
    (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
    amountToMint = (amountCollateral * (uint256(price) * fsce.getAdditionalFeedPrecision())) / fsce.getPrecision();
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(fsce), amountCollateral);

    uint256 expectedHealthFactor =
        fsce.calculateHealthFactor(amountToMint, fsce.getUsdValue(weth, amountCollateral));
    vm.expectRevert(abi.encodeWithSelector(FSCEngine.FSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
    fsce.depositCollateralAndMintFsc(weth, amountCollateral, amountToMint);
    vm.stopPrank();
  }

  modifier depositedCollateralAndMintedFsc() {
      vm.startPrank(user);
      ERC20Mock(weth).approve(address(fsce), amountCollateral);
      fsce.depositCollateralAndMintFsc(weth, amountCollateral, amountToMint);
      vm.stopPrank();
      _;
  }

  function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedFsc {
      uint256 userBalance = fsc.balanceOf(user);
      assertEq(userBalance, amountToMint);
  }

  /////////////
  // mintFsc tests //
  /////////////

  function testRevertsIfMintFails() public {
      // Arrange - Setup
      MockFailedMintFSC mockFsc = new MockFailedMintFSC();
      tokenAddresses = [weth];
      feedAddresses = [ethUsdPriceFeed];
      address owner = msg.sender;
      vm.prank(owner);
      FSCEngine mockFsce = new FSCEngine(
          tokenAddresses,
          feedAddresses,
          address(mockFsc)
      );
      mockFsc.transferOwnership(address(mockFsce));
      // Arrange - User
      vm.startPrank(user);
      ERC20Mock(weth).approve(address(mockFsce), amountCollateral);

      vm.expectRevert(FSCEngine.FSCEngine__MintFailed.selector);
      mockFsce.depositCollateralAndMintFsc(weth, amountCollateral, amountToMint);
      vm.stopPrank();
  }

  function testRevertsIfMintAmountIsZero() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(fsce), amountCollateral);
    fsce.depositCollateralAndMintFsc(weth, amountCollateral, amountToMint);
    vm.expectRevert(FSCEngine.FSCEngine__NeedsMoreThanZero.selector);
    fsce.mintFsc(0);
    vm.stopPrank();
  }

  function testRevertsIfMintAmountBreaksHealthFactor() public {
    // 0xe580cc6100000000000000000000000000000000000000000000000006f05b59d3b20000
    // 0xe580cc6100000000000000000000000000000000000000000000003635c9adc5dea00000
    (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
    amountToMint = (amountCollateral * (uint256(price) * fsce.getAdditionalFeedPrecision())) / fsce.getPrecision();

    vm.startPrank(user);
    ERC20Mock(weth).approve(address(fsce), amountCollateral);
    fsce.depositCollateral(weth, amountCollateral);

    uint256 expectedHealthFactor =
    fsce.calculateHealthFactor(amountToMint, fsce.getUsdValue(weth, amountCollateral));
    vm.expectRevert(abi.encodeWithSelector(FSCEngine.FSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
    fsce.mintFsc(amountToMint);
    vm.stopPrank();
  }

   function testCanMintFsc() public depositedCollateral {
    vm.prank(user);
    fsce.mintFsc(amountToMint);

    uint256 userBalance = fsc.balanceOf(user);
    assertEq(userBalance, amountToMint);
  }

  /////////////
  // burnFsc tests //
  /////////////
  function testRevertsIfBurnAmountIsZero() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(fsce), amountCollateral);
    fsce.depositCollateralAndMintFsc(weth, amountCollateral, amountToMint);
    vm.expectRevert(FSCEngine.FSCEngine__NeedsMoreThanZero.selector);
    fsce.burnFsc(0);
    vm.stopPrank();
  }

  function testCantBurnMoreThanUserHas() public {
    vm.prank(user);
    vm.expectRevert();
    fsce.burnFsc(1);
  }

  function testCanBurnFsc() public depositedCollateralAndMintedFsc {
    vm.startPrank(user);
    fsc.approve(address(fsce), amountToMint);
    fsce.burnFsc(amountToMint);
    vm.stopPrank();

    uint256 userBalance = fsc.balanceOf(user);
    assertEq(userBalance, 0);
  }

  /////////////
  // redeemCollateral tests //
  /////////////

  // this test needs it's own setup
  function testRevertsIfTransferFails() public {
    // Arrange - Setup
    address owner = msg.sender;
    vm.prank(owner);
    MockFailedTransfer mockFsc = new MockFailedTransfer();
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
    mockFsce.depositCollateral(address(mockFsc), amountCollateral);
    vm.expectRevert(FSCEngine.FSCEngine__TransferFailed.selector);
    mockFsce.redeemCollateral(address(mockFsc), amountCollateral);
    vm.stopPrank();
  }

  function testRevertsIfRedeemAmountIsZero() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(fsce), amountCollateral);
    fsce.depositCollateralAndMintFsc(weth, amountCollateral, amountToMint);
    vm.expectRevert(FSCEngine.FSCEngine__NeedsMoreThanZero.selector);
    fsce.redeemCollateral(weth, 0);
    vm.stopPrank();
  }

  function testCanRedeemCollateral() public depositedCollateral {
    vm.startPrank(user);
    fsce.redeemCollateral(weth, amountCollateral);
    uint256 userBalance = ERC20Mock(weth).balanceOf(user);
    assertEq(userBalance, amountCollateral);
    vm.stopPrank();
  }

  function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
    vm.expectEmit(true, true, true, true, address(fsce));
    emit CollateralRedeemed(user, user, weth, amountCollateral);
    vm.startPrank(user);
    fsce.redeemCollateral(weth, amountCollateral);
    vm.stopPrank();
  }

  /////////////
  // redeemCollateralForFsc tests //
  /////////////
  function testMustRedeemMoreThanZero() public depositedCollateralAndMintedFsc {
    vm.startPrank(user);
    fsc.approve(address(fsce), amountToMint);
    vm.expectRevert(FSCEngine.FSCEngine__NeedsMoreThanZero.selector);
    fsce.redeemCollateralForFsc(weth, 0, amountToMint);
    vm.stopPrank();
  }

  function testCanRedeemDepositedCollateral() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(fsce), amountCollateral);
    fsce.depositCollateralAndMintFsc(weth, amountCollateral, amountToMint);
    fsc.approve(address(fsce), amountToMint);
    fsce.redeemCollateralForFsc(weth, amountCollateral, amountToMint);
    vm.stopPrank();

    uint256 userBalance = fsc.balanceOf(user);
    assertEq(userBalance, 0);
  }

  /////////////
  // healthFactor tests //
  /////////////
  function testProperlyReportsHealthFactor() public depositedCollateralAndMintedFsc {
    uint256 expectedHealthFactor = 100 ether;
    uint256 healthFactor = fsce.getHealthFactor(user);
    // $100 minted with $20,000 collateral at 50% liquidation threshold
    // means that we must have $200 collatareral at all times.
    // 20,000 * 0.5 = 10,000
    // 10,000 / 100 = 100 health factor
    assertEq(healthFactor, expectedHealthFactor);
  }

  function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedFsc {
    int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
    // Rememeber, we need $150 at all times if we have $100 of debt

    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

    uint256 userHealthFactor = fsce.getHealthFactor(user);
    // $180 collateral / 200 debt = 0.9
    assert(userHealthFactor == 0.9 ether);
  }

  /////////////
  // Liquidation tests //
  /////////////
  // This test needs it's own setup
  function testMustImproveHealthFactorOnLiquidation() public {
    // Arrange - Setup
    MockMoreDebtFSC mockFsc = new MockMoreDebtFSC(ethUsdPriceFeed);
    tokenAddresses = [weth];
    feedAddresses = [ethUsdPriceFeed];
    address owner = msg.sender;
    vm.prank(owner);
    FSCEngine mockFsce = new FSCEngine(
        tokenAddresses,
        feedAddresses,
        address(mockFsc)
    );
    mockFsc.transferOwnership(address(mockFsce));
    // Arrange - User
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(mockFsce), amountCollateral);
    mockFsce.depositCollateralAndMintFsc(weth, amountCollateral, amountToMint);
    vm.stopPrank();

    // Arrange - Liquidator
    collateralToCover = 1 ether;
    ERC20Mock(weth).mint(liquidator, collateralToCover);

    vm.startPrank(liquidator);
    ERC20Mock(weth).approve(address(mockFsce), collateralToCover);
    uint256 debtToCover = 10 ether;
    mockFsce.depositCollateralAndMintFsc(weth, collateralToCover, amountToMint);
    mockFsc.approve(address(mockFsce), debtToCover);
    // Act
    int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
    // Act/Assert
    vm.expectRevert(FSCEngine.FSCEngine__HealthFactorNotImproved.selector);
    mockFsce.liquidate(weth, user, debtToCover);
    vm.stopPrank();
  }

  function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedFsc {
    ERC20Mock(weth).mint(liquidator, collateralToCover);

    vm.startPrank(liquidator);
    ERC20Mock(weth).approve(address(fsce), collateralToCover);
    fsce.depositCollateralAndMintFsc(weth, collateralToCover, amountToMint);
    fsc.approve(address(fsce), amountToMint);

    vm.expectRevert(FSCEngine.FSCEngine__HealthFactorOk.selector);
    fsce.liquidate(weth, user, amountToMint);
    vm.stopPrank();
  }

  modifier liquidated() {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(fsce), amountCollateral);
    fsce.depositCollateralAndMintFsc(weth, amountCollateral, amountToMint);
    vm.stopPrank();
    int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
    uint256 userHealthFactor = fsce.getHealthFactor(user);

    ERC20Mock(weth).mint(liquidator, collateralToCover);

    vm.startPrank(liquidator);
    ERC20Mock(weth).approve(address(fsce), collateralToCover);
    fsce.depositCollateralAndMintFsc(weth, collateralToCover, amountToMint);
    fsc.approve(address(fsce), amountToMint);
    fsce.liquidate(weth, user, amountToMint); // We are covering their whole debt
    vm.stopPrank();
    _;
  }

  function testLiquidationPayoutIsCorrect() public liquidated {
    uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
    uint256 expectedWeth = fsce.getTokenAmountFromUsd(weth, amountToMint)
    + (fsce.getTokenAmountFromUsd(weth, amountToMint) / fsce.getLiquidationBonus());
    uint256 hardCodedExpected = 6111111111111111110;
    assertEq(liquidatorWethBalance, hardCodedExpected);
    assertEq(liquidatorWethBalance, expectedWeth);
  }

  function testUserStillHasSomeEthAfterLiquidation() public liquidated {
    // Get how much WETH the user lost
    uint256 amountLiquidated = fsce.getTokenAmountFromUsd(weth, amountToMint)
    + (fsce.getTokenAmountFromUsd(weth, amountToMint) / fsce.getLiquidationBonus());

    uint256 usdAmountLiquidated = fsce.getUsdValue(weth, amountLiquidated);
    uint256 expectedUserCollateralValueInUsd = fsce.getUsdValue(weth, amountCollateral) - (usdAmountLiquidated);

    (, uint256 userCollateralValueInUsd) = fsce.getAccountInformation(user);
    uint256 hardCodedExpectedValue = 70000000000000000020;
    assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
    assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
  }

  function testLiquidatorTakesOnUsersDebt() public liquidated {
    (uint256 liquidatorFscMinted,) = fsce.getAccountInformation(liquidator);
    assertEq(liquidatorFscMinted, amountToMint);
  }

  function testUserHasNoMoreDebt() public liquidated {
    (uint256 userFscMinted,) = fsce.getAccountInformation(user);
    assertEq(userFscMinted, 0);
  }

  /////////////
  // View & pure function tests //
  /////////////
  function testGetCollateralTokenPriceFeed() public {
    address priceFeed = fsce.getCollateralTokenPriceFeed(weth);
    assertEq(priceFeed, ethUsdPriceFeed);
  }

  function testGetCollateralTokens() public {
    address[] memory collateralTokens = fsce.getCollateralTokens();
    assertEq(collateralTokens[0], weth);
  }

  function testGetMinHealthFactor() public {
    uint256 minHealthFactor = fsce.getMinHealthFactor();
    assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
  }

  function testGetLiquidationThreshold() public {
    uint256 liquidationThreshold = fsce.getLiquidationThreshold();
    assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
  }

  function testGetAccountCollateralValueFromInformation() public depositedCollateral {
    (, uint256 collateralValue) = fsce.getAccountInformation(user);
    uint256 expectedCollateralValue = fsce.getUsdValue(weth, amountCollateral);
    assertEq(collateralValue, expectedCollateralValue);
  }

  function testGetCollateralBalanceOfUser() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(fsce), amountCollateral);
    fsce.depositCollateral(weth, amountCollateral);
    vm.stopPrank();
    uint256 collateralBalance = fsce.getCollateralBalanceOfUser(user, weth);
    assertEq(collateralBalance, amountCollateral);
  }

  function testGetAccountCollateralValue() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(fsce), amountCollateral);
    fsce.depositCollateral(weth, amountCollateral);
    vm.stopPrank();
    uint256 collateralValue = fsce.getAccountCollateralValue(user);
    uint256 expectedCollateralValue = fsce.getUsdValue(weth, amountCollateral);
    assertEq(collateralValue, expectedCollateralValue);
  }

  function testGetFsc() public {
    address fscAddress = fsce.getFsc();
    assertEq(fscAddress, address(fsc));
  }
}
