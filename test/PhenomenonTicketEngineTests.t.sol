// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Phenomenon} from "../src/Phenomenon.sol";
import {GameplayEngine} from "../src/GameplayEngine.sol";
import {PhenomenonTicketEngine} from "../src/PhenomenonTicketEngine.sol";
import {DeployPhenomenon} from "../script/DeployPhenomenon.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {MockFunctionsRouterSimple} from "./mocks/MockFunctionsRouterSimple.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {GameplayEngineHelper} from "./mocks/GameplayEngineHelper.sol";
import {console2} from "forge-std/console2.sol";

contract PhenomenonTicketEngineTests is Test {
    GameplayEngine public gameplayEngine;
    GameplayEngineHelper public gameplayEngineHelper;
    Phenomenon public phenomenon;
    PhenomenonTicketEngine public phenomenonTicketEngine;
    HelperConfig public helperConfig;
    MockFunctionsRouterSimple public mockFunctionsRouterSimple;

    address public chainlinkFunctionsRouter;
    bytes32 public chainlinkFunctionsDONID;
    address public weth;
    uint256 public deployerKey;
    address public owner;
    address public user1 = address(1);
    address public user2 = address(2);
    address public user3 = address(3);
    address public user4 = address(4);
    address public user5 = address(5);
    address public newOwner = address(6);

    // Events for testing
    event religionLost(
        uint256 indexed _target, uint256 indexed numTicketsSold, uint256 indexed totalPrice, address sender
    );
    event gainReligion(
        uint256 indexed _target, uint256 indexed numTicketsBought, uint256 indexed totalPrice, address sender
    );
    event ticketsClaimed(address indexed player, uint256 indexed tokensSent, uint256 indexed gameNumber);

    function setUp() public {
        DeployPhenomenon deployer = new DeployPhenomenon();
        (
            chainlinkFunctionsRouter,
            chainlinkFunctionsDONID,
            weth,
            deployerKey,
            phenomenon,
            phenomenonTicketEngine,
            gameplayEngine
        ) = deployer.run();

        owner = gameplayEngine.getOwner();
        mockFunctionsRouterSimple = MockFunctionsRouterSimple(chainlinkFunctionsRouter);
        gameplayEngineHelper = new GameplayEngineHelper(
            address(phenomenon),
            "return Functions.encodeString('Hello World!');",
            uint64(123),
            chainlinkFunctionsRouter,
            chainlinkFunctionsDONID
        );

        // Mint tokens for testing
        ERC20Mock(weth).mint(user1, 1000 ether);
        ERC20Mock(weth).mint(user2, 1000 ether);
        ERC20Mock(weth).mint(user3, 1000 ether);
        ERC20Mock(weth).mint(user4, 1000 ether);
        ERC20Mock(weth).mint(user5, 100000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                       OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnerCanChangeOwner() public {
        vm.startPrank(owner);
        phenomenonTicketEngine.changeOwner(newOwner);
        vm.stopPrank();
    }

    function testNonOwnerCannotChangeOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        phenomenonTicketEngine.changeOwner(newOwner);
        vm.stopPrank();
    }

    function testOwnerCanSetTicketMultiplier() public {
        vm.startPrank(owner);
        phenomenonTicketEngine.setTicketMultiplier(2000);
        vm.stopPrank();
    }

    function testNonOwnerCannotSetTicketMultiplier() public {
        vm.startPrank(user1);
        vm.expectRevert();
        phenomenonTicketEngine.setTicketMultiplier(2000);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       HIGH PRIEST TESTS
    //////////////////////////////////////////////////////////////*/

    function setupGameWithFourProphets() private {
        // Reset to a clean game state with 4 prophets
        vm.startPrank(owner);
        phenomenon.reset(4);
        vm.stopPrank();

        // Register 4 prophets
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        gameplayEngine.enterGame(new bytes32[](0));
        vm.stopPrank();

        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        gameplayEngine.enterGame(new bytes32[](0));
        vm.stopPrank();

        vm.startPrank(user3);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        gameplayEngine.enterGame(new bytes32[](0));
        vm.stopPrank();

        vm.startPrank(user4);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        gameplayEngine.enterGame(new bytes32[](0));
        vm.stopPrank();

        // Generate a mock requestId for testing
        bytes32 mockRequestId = keccak256(abi.encode(block.timestamp, address(gameplayEngine), "testRequest"));

        // Set this mock requestId using a low-level storage write
        vm.store(
            address(gameplayEngine),
            bytes32(uint256(5)), // slot for s_lastFunctionRequestId
            mockRequestId
        );
        vm.store(
            address(gameplayEngineHelper),
            bytes32(uint256(5)), // slot for s_lastFunctionRequestId
            mockRequestId
        );

        // Transfer control of Phenomenon contract to GameplayEngineHelper
        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngineHelper));
        vm.stopPrank();

        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();
        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("1011");
        vm.prank(address(mockFunctionsRouterSimple));
        gameplayEngineHelper.fulfillRequestHarness(requestId, response, "");

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
    }

    function testProphetCanChangeAllegiance() public {
        setupGameWithFourProphets();

        // Prophet 0 (user1) should be able to change allegiance to prophet 2
        vm.startPrank(user1);
        phenomenonTicketEngine.highPriest(0, 2);
        vm.stopPrank();

        // Check that allegiance was changed
        assertEq(phenomenon.allegiance(phenomenon.s_gameNumber(), user1), 2);
        // Check that tickets were properly assigned
        assertEq(phenomenon.ticketsToValhalla(phenomenon.s_gameNumber(), user1), 1);
        assertEq(phenomenon.getTicketShare(0), 0);
        assertEq(phenomenon.getTicketShare(2), 50);
        assertEq(phenomenon.highPriestsByProphet(0), 0);
        assertEq(phenomenon.highPriestsByProphet(2), 2);
        assertEq(phenomenon.acolytes(0), 0);
        assertEq(phenomenon.acolytes(2), 0);
    }

    function testHighPriestCanChangeAllegiance() public {
        setupGameWithFourProphets();

        // Prophet 1 (user2) should be able to change allegiance to prophet 2
        vm.startPrank(user2);
        phenomenonTicketEngine.highPriest(1, 2);
        vm.stopPrank();

        // Check that allegiance was changed
        assertEq(phenomenon.allegiance(phenomenon.s_gameNumber(), user2), 2);
        // Check that tickets were properly assigned
        assertEq(phenomenon.ticketsToValhalla(phenomenon.s_gameNumber(), user2), 1);
        assertEq(phenomenon.getTicketShare(1), 0);
        assertEq(phenomenon.getTicketShare(2), 50);
        assertEq(phenomenon.highPriestsByProphet(1), 0);
        assertEq(phenomenon.highPriestsByProphet(2), 2);
        assertEq(phenomenon.acolytes(1), 0);
        assertEq(phenomenon.acolytes(2), 0);
    }

    function testHighPriestCannotChangeAllegianceIfFollwingDeadProphet() public {
        setupGameWithFourProphets();

        // Set Prophet 0 allegiance to Prophet 3
        vm.startPrank(user1);
        phenomenonTicketEngine.highPriest(0, 3);
        vm.stopPrank();

        // Kill prophet 3
        vm.startPrank(address(gameplayEngine));
        phenomenon.updateProphetLife(3, false);
        vm.stopPrank();

        // Prophet 0 (user1) should not be able to change allegiance
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__AddressIsEliminated.selector));
        phenomenonTicketEngine.highPriest(0, 0);
        vm.stopPrank();
    }

    function testHighPriestCannotChangeAllegianceIfTooFewProphetsRemaining() public {
        setupGameWithFourProphets();

        // Kill prophet 3
        vm.startPrank(address(gameplayEngine));
        phenomenon.updateProphetLife(3, false);
        phenomenon.updateProphetsRemaining(0, 1);
        vm.stopPrank();

        // Prophet 0 (user1) should not be able to change allegiance
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotAllowed.selector));
        phenomenonTicketEngine.highPriest(0, 0);
        vm.stopPrank();
    }

    function testProphetCannotChangeAllegianceIfKilled() public {
        setupGameWithFourProphets();

        // Kill prophet 3
        vm.startPrank(address(gameplayEngine));
        phenomenon.updateProphetLife(3, false);
        vm.stopPrank();

        // Prophet 3 (user4) should not be able to change allegiance
        vm.startPrank(user4);
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotAllowed.selector));
        phenomenonTicketEngine.highPriest(3, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       GET RELIGION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanBuyTickets() public {
        setupGameWithFourProphets();
        uint256 tokensDeposited = phenomenon.s_tokensDepositedThisGame();

        // User5 (non-prophet) buys tickets for prophet 0
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 100000 ether);
        uint256 price = phenomenonTicketEngine.getPrice(0, 5);
        vm.expectEmit(true, true, true, false);
        emit gainReligion(0, 5, price, user5);
        phenomenonTicketEngine.getReligion(0, 5);
        tokensDeposited += price;
        vm.stopPrank();

        // Check that tickets were properly assigned
        assertEq(phenomenon.ticketsToValhalla(phenomenon.s_gameNumber(), user5), 5);
        assertEq(phenomenon.acolytes(0), 5);
        assertEq(phenomenon.s_totalTickets(), 9);
        assertEq(phenomenon.s_tokensDepositedThisGame(), tokensDeposited);
        assertEq(phenomenon.allegiance(phenomenon.s_gameNumber(), user5), 0);
        assertEq(phenomenon.getTicketShare(0), 66);

        // Check tokens were transfered from User5 to Phenomenon
        assertEq(ERC20Mock(weth).balanceOf(user5), 100000 ether - price);
        assertEq(ERC20Mock(weth).balanceOf(address(phenomenon)), tokensDeposited);
    }

    function testCannotBuyTicketsOfDeadProphet() public {
        setupGameWithFourProphets();

        // Kill prophet 0
        vm.startPrank(address(gameplayEngine));
        phenomenon.updateProphetLife(0, false);
        vm.stopPrank();

        // User5 tries to buy tickets of dead prophet
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 100 ether);
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__ProphetIsDead.selector));
        phenomenonTicketEngine.getReligion(0, 1);

        // User5 tries to buy tickets of High Priest
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__ProphetIsDead.selector));
        phenomenonTicketEngine.getReligion(1, 1);
        vm.stopPrank();
    }

    function testCannotBuyTicketsIfNotInProgress() public {
        setupGameWithFourProphets();

        // Change game state to Open
        vm.startPrank(address(gameplayEngine));
        phenomenon.changeGameStatus(0);
        vm.stopPrank();

        // User5 tries to buy tickets of dead prophet
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 1000 ether);
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotInProgress.selector));
        phenomenonTicketEngine.getReligion(0, 1);
        vm.stopPrank();

        // Change game state to awaiting response
        vm.startPrank(address(gameplayEngine));
        phenomenon.changeGameStatus(2);
        vm.stopPrank();

        // User5 tries to buy tickets of dead prophet
        vm.startPrank(user5);
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotInProgress.selector));
        phenomenonTicketEngine.getReligion(0, 1);
        vm.stopPrank();

        // Change game state to Ended
        vm.startPrank(address(gameplayEngine));
        phenomenon.changeGameStatus(4);
        vm.stopPrank();

        // User5 tries to buy tickets of dead prophet
        vm.startPrank(user5);
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotInProgress.selector));
        phenomenonTicketEngine.getReligion(0, 1);
        vm.stopPrank();
    }

    function testCannotBuyZeroTickets() public {
        setupGameWithFourProphets();

        // User5 tries to buy 0 tickets
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 1000 ether);
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotAllowed.selector));
        phenomenonTicketEngine.getReligion(0, 0);
        vm.stopPrank();
    }

    function testCannotBuyTicketsIfProphet() public {
        setupGameWithFourProphets();

        // User1 tries to buy 1 tickets
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), 1000 ether);
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotAllowed.selector));
        phenomenonTicketEngine.getReligion(0, 1);
        vm.stopPrank();
    }

    function testCannotBuyTicketsOfSecondProphet() public {
        setupGameWithFourProphets();

        // User5 tries to buy 1 ticket of prophet 0 then 1 of prophet 2
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 1000 ether);
        phenomenonTicketEngine.getReligion(0, 1);
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotAllowed.selector));
        phenomenonTicketEngine.getReligion(2, 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       LOSE RELIGION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanSellTickets() public {
        setupGameWithFourProphets();

        // First buy 2 tickets
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 100000 ether);
        uint256 price1 = phenomenonTicketEngine.getPrice(0, 2);
        uint256 user5StartingBalance = ERC20Mock(weth).balanceOf(user5);
        phenomenonTicketEngine.getReligion(0, 2);

        // Then Sell 1 ticket
        uint256 ticketsToSell = 1;
        uint256 tokensDeposited = phenomenon.s_tokensDepositedThisGame();
        // i_gameContract.acolytes(currentAllegiance) - _ticketsToSell, _ticketsToSell
        uint256 price2 = phenomenonTicketEngine.getPrice(phenomenon.acolytes(0) - ticketsToSell, ticketsToSell);
        // Then sell one ticket
        vm.expectEmit(true, true, true, false);
        emit religionLost(0, ticketsToSell, price2, user5);
        phenomenonTicketEngine.loseReligion(ticketsToSell);
        vm.stopPrank();

        // Check that tickets were properly updated
        assertEq(phenomenon.ticketsToValhalla(phenomenon.s_gameNumber(), user5), 1);
        // Check total tickets equals 5
        assertEq(phenomenon.s_totalTickets(), 5);
        // Check Accolytes of prophet 0 equals 1
        assertEq(phenomenon.acolytes(0), 1);
        //Check user5 allegiance is set to prophet 0
        assertEq(phenomenon.allegiance(phenomenon.s_gameNumber(), user5), 0);
        // Check tokens deposited this game is appropriately decreased
        assertEq(phenomenon.s_tokensDepositedThisGame(), tokensDeposited - price2);
        // Check user5 token balance is correct and protocol fee was applied
        assertEq(
            ERC20Mock(weth).balanceOf(user5),
            user5StartingBalance - price1 + (price2 * (10000 - phenomenon.s_protocolFee()) / 10000)
        );
    }

    function testCannotSellMoreTicketsThanOwned() public {
        setupGameWithFourProphets();

        // Buy 1 ticket
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 100000 ether);
        phenomenonTicketEngine.getReligion(0, 1);

        // Try to sell 2 tickets
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotEnoughTicketsOwned.selector));
        phenomenonTicketEngine.loseReligion(2);
        vm.stopPrank();
    }

    function testCanBuyOtherProphetTicketsAfterSellingAll() public {
        setupGameWithFourProphets();

        // First buy 2 tickets
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 100000 ether);
        phenomenonTicketEngine.getReligion(0, 2);

        // Then Sell both tickets
        uint256 ticketsToSell = 2;
        phenomenonTicketEngine.loseReligion(ticketsToSell);

        // Finally, buy 1 ticket of prophet 2
        phenomenonTicketEngine.getReligion(2, 1);
        vm.stopPrank();

        // Check that tickets were properly updated
        assertEq(phenomenon.ticketsToValhalla(phenomenon.s_gameNumber(), user5), 1);
        // Check total tickets equals 5
        assertEq(phenomenon.s_totalTickets(), 5);
        // Check Acolytes of prophet 0 equals 0
        assertEq(phenomenon.acolytes(0), 0);
        // Check Acolytes of prophet 2 equals 1
        assertEq(phenomenon.acolytes(2), 1);
        //Check user5 allegiance is set to prophet 2
        assertEq(phenomenon.allegiance(phenomenon.s_gameNumber(), user5), 2);
        //Check ticketShare of prophets 0 and 2 (1 of 5 and 2 of 5, respectively)
        assertEq(phenomenon.getTicketShare(0), 20);
        assertEq(phenomenon.getTicketShare(2), 40);
    }

    /*//////////////////////////////////////////////////////////////
                       CLAIM TICKETS TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanClaimTicketsAfterGameEnds() public {
        setupGameWithFourProphets();

        // Buy tickets for prophet 0
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 100 ether);
        phenomenonTicketEngine.getReligion(0, 1);
        vm.stopPrank();

        // End the game with prophet 0 as winner
        vm.startPrank(address(gameplayEngine));
        phenomenon.updateProphetLife(1, false);
        phenomenon.updateProphetLife(2, false);
        phenomenon.updateProphetLife(3, false);
        phenomenon.updateProphetsRemaining(0, 3);
        phenomenon.turnManager();
        vm.stopPrank();

        // Start new game
        vm.startPrank(owner);
        phenomenon.reset(4);
        vm.stopPrank();

        // Claim tickets from previous game
        vm.startPrank(user5);
        phenomenonTicketEngine.claimTickets(phenomenon.s_gameNumber() - 1, user5);
        vm.stopPrank();
    }

    function testCannotClaimTicketsFromCurrentGame() public {
        setupGameWithFourProphets();

        // Buy tickets for prophet 0
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 100 ether);
        phenomenonTicketEngine.getReligion(0, 1);

        // Try to claim tickets from current game
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotAllowed.selector));
        phenomenonTicketEngine.claimTickets(phenomenon.s_gameNumber(), user5);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       PRICE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetPrice() public view {
        // Test price calculation with different supplies and amounts
        uint256 price1 = phenomenonTicketEngine.getPrice(0, 1);
        uint256 price2 = phenomenonTicketEngine.getPrice(1, 1);
        uint256 price3 = phenomenonTicketEngine.getPrice(2, 2);

        // Price should increase with supply
        assertGt(price2, price1);
        assertGt(price3, price2);
    }
}
