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
        ERC20Mock(weth).mint(user5, 1000 ether);
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

    function testHighPriestCanChangeAllegiance() public {
        setupGameWithFourProphets();

        // Prophet 0 (user1) should be able to change allegiance to prophet 2
        vm.startPrank(user1);
        phenomenonTicketEngine.highPriest(0, 2);
        vm.stopPrank();

        // Check that allegiance was changed
        assertEq(phenomenon.allegiance(phenomenon.s_gameNumber(), user1), 2);
    }

    function testCannotHighPriestToDeadProphet() public {
        setupGameWithFourProphets();

        // Kill prophet 2
        vm.startPrank(address(gameplayEngine));
        phenomenon.updateProphetLife(2, false);
        vm.stopPrank();

        // Prophet 0 (user1) should not be able to change allegiance to dead prophet 2
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotAllowed.selector));
        phenomenonTicketEngine.highPriest(0, 2);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       GET RELIGION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanBuyTickets() public {
        setupGameWithFourProphets();

        // User5 (non-prophet) buys tickets for prophet 0
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 100 ether);
        phenomenonTicketEngine.getReligion(0, 1);
        vm.stopPrank();

        // Check that tickets were properly assigned
        assertEq(phenomenon.ticketsToValhalla(phenomenon.s_gameNumber(), user5), 1);
        assertEq(phenomenon.allegiance(phenomenon.s_gameNumber(), user5), 0);
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
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       LOSE RELIGION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanSellTickets() public {
        setupGameWithFourProphets();

        // First buy some tickets
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 100 ether);
        phenomenonTicketEngine.getReligion(0, 2);

        // Then sell one ticket
        phenomenonTicketEngine.loseReligion(1);
        vm.stopPrank();

        // Check that tickets were properly updated
        assertEq(phenomenon.ticketsToValhalla(phenomenon.s_gameNumber(), user5), 1);
    }

    function testCannotSellMoreTicketsThanOwned() public {
        setupGameWithFourProphets();

        // Buy 1 ticket
        vm.startPrank(user5);
        ERC20Mock(weth).approve(address(phenomenon), 100 ether);
        phenomenonTicketEngine.getReligion(0, 1);

        // Try to sell 2 tickets
        vm.expectRevert(abi.encodeWithSelector(PhenomenonTicketEngine.TicketEng__NotEnoughTicketsOwned.selector));
        phenomenonTicketEngine.loseReligion(2);
        vm.stopPrank();
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

    function testGetPrice() public {
        // Test price calculation with different supplies and amounts
        uint256 price1 = phenomenonTicketEngine.getPrice(0, 1);
        uint256 price2 = phenomenonTicketEngine.getPrice(1, 1);
        uint256 price3 = phenomenonTicketEngine.getPrice(2, 2);

        // Price should increase with supply
        assertGt(price2, price1);
        assertGt(price3, price2);
    }
}
