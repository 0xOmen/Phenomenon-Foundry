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

contract GameplayEngineTests is Test {
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
    event prophetEnteredGame(uint256 indexed prophetNumber, address indexed sender, uint256 indexed gameNumber);
    event gameStarted(uint256 indexed gameNumber);
    event miracleAttempted(bool indexed isSuccess, uint256 indexed currentProphetTurn);
    event smiteAttempted(uint256 indexed target, bool indexed isSuccess, uint256 indexed currentProphetTurn);
    event accusation(
        bool indexed isSuccess, bool targetIsAlive, uint256 indexed currentProphetTurn, uint256 indexed _target
    );
    event Response(bytes32 indexed requestId, string character, bytes response, bytes err);

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
        // set owner to the owner of the phenomenon contract
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

    function testOwnerCanChangeSubscriptionId() public {
        vm.startPrank(owner);
        gameplayEngine.changeFunctionsSubscriptionId(123);
        vm.stopPrank();
    }

    function testNonOwnerCannotChangeSubscriptionId() public {
        vm.startPrank(user1);
        vm.expectRevert("Only callable by owner");
        gameplayEngine.changeFunctionsSubscriptionId(123);
        vm.stopPrank();
    }

    function testAllNonOwnerFunctionsAreRestricted() public {
        vm.startPrank(user1);
        vm.expectRevert("Only callable by owner");
        gameplayEngine.changeFunctionsSubscriptionId(123);
        vm.expectRevert("Only callable by owner");
        gameplayEngine.setAllowListEnabled(true);
        vm.expectRevert("Only callable by owner");
        gameplayEngine.resetAllowListRoot(bytes32(0));
        vm.expectRevert("Only callable by owner");
        gameplayEngine.setSource("");
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       ENTER GAME TESTS
    //////////////////////////////////////////////////////////////*/

    function testPlayerCanEnterGame() public {
        // First reset to a clean game state
        vm.startPrank(owner);
        phenomenon.reset(4);
        vm.stopPrank();

        // Approve tokens for game entry
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());

        // Expect the prophetEnteredGame event
        vm.expectEmit(true, true, true, false);
        emit prophetEnteredGame(0, user1, phenomenon.s_gameNumber());

        // Enter the game
        gameplayEngine.enterGame(new bytes32[](0));
        vm.stopPrank();

        // Verify player was registered
        assertEq(phenomenon.prophetList(phenomenon.s_gameNumber(), user1), true);
        assertEq(phenomenon.s_prophetsRemaining(), 1);
    }

    function testCannotEnterGameIfAlreadyRegistered() public {
        // First reset to a clean game state
        vm.startPrank(owner);
        phenomenon.reset(4);
        vm.stopPrank();

        // User1 enters the game
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        gameplayEngine.enterGame(new bytes32[](0));

        // Try to enter again - should revert
        vm.expectRevert(abi.encodeWithSelector(GameplayEngine.GameEng__AlreadyRegistered.selector));
        gameplayEngine.enterGame(new bytes32[](0));
        vm.stopPrank();
    }

    function testGameStartsWhenFull() public {
        // First reset to a clean game state with 4 prophets
        vm.startPrank(owner);
        phenomenon.reset(4);
        vm.stopPrank();

        // User1, User2, User3 enter the game
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

        // User4 enters and fills the game
        vm.startPrank(user4);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());

        // Enter and fill the game
        gameplayEngine.enterGame(new bytes32[](0));
        vm.stopPrank();

        // Game should now be in AWAITING_RESPONSE state (2) after sending request
        assertEq(uint256(phenomenon.gameStatus()), 2);
    }

    function testCannotEnterGameIfNotOpen() public {
        // First reset to a clean game state
        vm.startPrank(owner);
        phenomenon.reset(4);

        // Change game status to IN_PROGRESS
        phenomenon.ownerChangeGameState(Phenomenon.GameState.IN_PROGRESS);
        vm.stopPrank();

        // Try to enter game
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());

        vm.expectRevert(abi.encodeWithSelector(GameplayEngine.GameEng__NotOpen.selector));
        gameplayEngine.enterGame(new bytes32[](0));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       GAMEPLAY TESTS
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
        console2.logBytes(response);
        vm.prank(address(mockFunctionsRouterSimple));
        gameplayEngineHelper.fulfillRequestHarness(requestId, response, "");

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
    }

    function testFunctionsRouterAppropriatelySetsUpGame() public {
        setupGameWithFourProphets();

        // Check that the game is in IN_PROGRESS state
        assertEq(uint256(phenomenon.gameStatus()), 1);
        assertEq(phenomenon.s_prophetsRemaining(), 3);

        // Check that the prophets are set up correctly
        (address prophet1, bool isAlive1, bool isFree1, uint256 args1) = phenomenon.getProphetData(0);
        assertEq(prophet1, user1);
        assertTrue(isAlive1);
        assertTrue(isFree1);
        assertEq(args1, 0);

        (address prophet2, bool isAlive2, bool isFree2, uint256 args2) = phenomenon.getProphetData(1);
        assertEq(prophet2, user2);
        assertFalse(isAlive2);
        assertTrue(isFree2);
        assertEq(args2, 99);

        (address prophet3, bool isAlive3, bool isFree3, uint256 args3) = phenomenon.getProphetData(2);
        assertEq(prophet3, user3);
        assertTrue(isAlive3);
        assertTrue(isFree3);
        assertEq(args3, 0);

        (address prophet4, bool isAlive4, bool isFree4, uint256 args4) = phenomenon.getProphetData(3);
        assertEq(prophet4, user4);
        assertTrue(isAlive4);
        assertTrue(isFree4);
        assertEq(args4, 0);

        // Check ticket system is correct
        assertEq(phenomenon.ticketsToValhalla(phenomenon.s_gameNumber(), user1), 1);
        assertEq(phenomenon.ticketsToValhalla(phenomenon.s_gameNumber(), user2), 1);
        assertEq(phenomenon.ticketsToValhalla(phenomenon.s_gameNumber(), user3), 1);
        assertEq(phenomenon.ticketsToValhalla(phenomenon.s_gameNumber(), user4), 1);
        assertEq(phenomenon.s_totalTickets(), 4);

        // Check ticketShare is 1/n players
        assertEq(phenomenon.getTicketShare(0), 25);
        assertEq(phenomenon.getTicketShare(1), 25);
        assertEq(phenomenon.getTicketShare(2), 25);
        assertEq(phenomenon.getTicketShare(3), 25);

        // Check allegiance is correct
        uint256 currentGameNumber = phenomenon.s_gameNumber();
        assertEq(phenomenon.allegiance(currentGameNumber, user1), 0);
        assertEq(phenomenon.allegiance(currentGameNumber, user2), 1);
        assertEq(phenomenon.allegiance(currentGameNumber, user3), 2);
        assertEq(phenomenon.allegiance(currentGameNumber, user4), 3);

        // Check acolytes is correct
        assertEq(phenomenon.acolytes(0), 0);
        assertEq(phenomenon.acolytes(1), 0);
        assertEq(phenomenon.acolytes(2), 0);
        assertEq(phenomenon.acolytes(3), 0);

        // Check high priests is correct
        assertEq(phenomenon.highPriestsByProphet(0), 1);
        assertEq(phenomenon.highPriestsByProphet(1), 1);
        assertEq(phenomenon.highPriestsByProphet(2), 1);
        assertEq(phenomenon.highPriestsByProphet(3), 1);
    }

    function testPerformMiracleSuccess() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // User1 performs a miracle
        vm.startPrank(user1);
        gameplayEngine.performMiracle();
        vm.stopPrank();

        // Game should be in AWAITING_RESPONSE state
        assertEq(uint256(phenomenon.gameStatus()), 2);

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngineHelper));
        vm.stopPrank();

        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();
        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("1");
        console2.logBytes(response);

        // Simulate successful miracle response ("1")
        vm.expectEmit(true, true, false, false);
        emit miracleAttempted(true, 0);

        vm.prank(address(mockFunctionsRouterSimple));
        gameplayEngineHelper.fulfillRequestHarness(requestId, response, "");

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();

        // Prophet should still be alive and free
        (, bool isAlive, bool isFree,) = phenomenon.getProphetData(0);
        assertTrue(isAlive);
        assertTrue(isFree);

        // Game should be back to IN_PROGRESS
        assertEq(uint256(phenomenon.gameStatus()), 1);
        // check that the prophet turn is 2
        assertEq(phenomenon.currentProphetTurn(phenomenon.s_gameNumber()), 2);
    }

    function testPerformMiracleFail() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // User1 performs a miracle
        vm.startPrank(user1);
        gameplayEngine.performMiracle();
        vm.stopPrank();

        // Game should be in AWAITING_RESPONSE state
        assertEq(uint256(phenomenon.gameStatus()), 2);

        // Start fullfillRequest Sequence
        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngineHelper));
        vm.stopPrank();

        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();
        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("0");
        console2.logBytes(response);

        // Simulate unsuccessful miracle response ("0")
        vm.expectEmit(true, true, false, false);
        emit miracleAttempted(false, 0);

        vm.prank(address(mockFunctionsRouterSimple));
        gameplayEngineHelper.fulfillRequestHarness(requestId, response, "");

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
        ///////////// End fullfillRequest Sequence /////////////

        // Game should be back to IN_PROGRESS
        assertEq(uint256(phenomenon.gameStatus()), 1);
        // check that the prophet turn is 2
        assertEq(phenomenon.currentProphetTurn(phenomenon.s_gameNumber()), 2);

        // Prophet should be dead
        (, bool isAlive,,) = phenomenon.getProphetData(0);
        assertFalse(isAlive);

        // Prophets remaining should be reduced by 1
        assertEq(phenomenon.s_prophetsRemaining(), 2);
    }

    function testAttemptSmiteSuccess() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // User1 attempts to smite user2 (prophet 2)
        vm.startPrank(user1);
        gameplayEngine.attemptSmite(2);
        vm.stopPrank();

        ///////////// Start fullfillRequest Sequence /////////////
        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngineHelper));
        vm.stopPrank();

        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();
        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("3");
        console2.logBytes(response);

        // Simulate successful smite response ("3")
        vm.expectEmit(true, true, true, false);
        emit smiteAttempted(2, true, 0);

        vm.prank(address(mockFunctionsRouterSimple));
        gameplayEngineHelper.fulfillRequestHarness(requestId, response, "");

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
        ///////////// End fullfillRequest Sequence /////////////

        // Target prophet should be dead
        (, bool isTargetAlive,,) = phenomenon.getProphetData(2);
        assertFalse(isTargetAlive);

        // Prophets remaining should be reduced by 1
        assertEq(phenomenon.s_prophetsRemaining(), 2);

        // check that the prophet turn is 3
        assertEq(phenomenon.currentProphetTurn(phenomenon.s_gameNumber()), 3);
    }

    function testAttemptSmiteFail() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // User1 attempts to smite user2 (prophet 2)
        vm.startPrank(user1);
        gameplayEngine.attemptSmite(2);
        vm.stopPrank();

        ///////////// Start fullfillRequest Sequence /////////////
        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngineHelper));
        vm.stopPrank();

        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();
        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("2");
        console2.logBytes(response);

        // Simulate failed smite response ("2")
        vm.expectEmit(true, true, true, false);
        emit smiteAttempted(2, false, 0);

        vm.prank(address(mockFunctionsRouterSimple));
        gameplayEngineHelper.fulfillRequestHarness(requestId, response, "");

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
        ///////////// End fullfillRequest Sequence /////////////

        // Attacker should be jailed
        (,, bool isAttackerFree,) = phenomenon.getProphetData(0);
        assertFalse(isAttackerFree);

        // Target prophet should still be alive
        (, bool isTargetAlive,,) = phenomenon.getProphetData(2);
        assertTrue(isTargetAlive);
        // Prophets remaining should be unchanged
        assertEq(phenomenon.s_prophetsRemaining(), 3);

        // check that the prophet turn is 2
        assertEq(phenomenon.currentProphetTurn(phenomenon.s_gameNumber()), 2);
    }

    function testAccuseOfBlasphemySuccess() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // User1 accuses user4 (prophet 3) of blasphemy
        vm.startPrank(user1);
        gameplayEngine.accuseOfBlasphemy(3);
        vm.stopPrank();

        ///////////// Start fullfillRequest Sequence /////////////
        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngineHelper));
        vm.stopPrank();

        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();
        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("5");
        console2.logBytes(response);

        // Simulate successful accusation response ("5")
        vm.expectEmit(true, false, false, false);
        emit accusation(true, true, 0, 3);

        vm.prank(address(mockFunctionsRouterSimple));
        gameplayEngineHelper.fulfillRequestHarness(requestId, response, "");

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
        ///////////// End fullfillRequest Sequence /////////////

        // Target prophet should be jailed
        (, bool isTargetAlive, bool isTargetFree,) = phenomenon.getProphetData(3);
        assertFalse(isTargetFree);

        // But still alive
        assertTrue(isTargetAlive);

        // Check successful accusation of jailed prophet
        // User3 accuses user4 (prophet 3) of blasphemy
        vm.startPrank(user3);
        gameplayEngine.accuseOfBlasphemy(3);
        vm.stopPrank();

        ///////////// Start fullfillRequest Sequence /////////////
        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngineHelper));
        vm.stopPrank();

        requestId = gameplayEngine.s_lastFunctionRequestId();
        response = mockFunctionsRouterSimple._fulfillRequest("5");
        console2.logBytes(response);

        // Simulate successful accusation response ("5")
        vm.expectEmit(true, false, false, false);
        emit accusation(true, false, 2, 3);

        vm.prank(address(mockFunctionsRouterSimple));
        gameplayEngineHelper.fulfillRequestHarness(requestId, response, "");

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
        ///////////// End fullfillRequest Sequence /////////////

        // Target prophet should be jailed
        (, isTargetAlive, isTargetFree,) = phenomenon.getProphetData(3);
        assertFalse(isTargetFree);

        // And dead
        assertFalse(isTargetAlive);

        // Number of players remaining should be 2
        assertEq(phenomenon.s_prophetsRemaining(), 2);
    }

    function testOutOfJailOnMiracle() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // User1 accuses user3 (prophet 2) of blasphemy
        vm.startPrank(user1);
        gameplayEngine.accuseOfBlasphemy(2);
        vm.stopPrank();

        ///////////// Start fullfillRequest Sequence /////////////
        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngineHelper));
        vm.stopPrank();

        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();
        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("5");
        console2.logBytes(response);

        // Simulate successful accusation response ("5")
        vm.expectEmit(true, false, false, false);
        emit accusation(true, true, 0, 2);

        vm.prank(address(mockFunctionsRouterSimple));
        gameplayEngineHelper.fulfillRequestHarness(requestId, response, "");

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
        ///////////// End fullfillRequest Sequence /////////////

        // User3 performs miracle to get out of jail
        vm.startPrank(user3);
        gameplayEngine.performMiracle();
        vm.stopPrank();

        ///////////// Start fullfillRequest Sequence /////////////
        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngineHelper));
        vm.stopPrank();

        requestId = gameplayEngine.s_lastFunctionRequestId();
        response = mockFunctionsRouterSimple._fulfillRequest("1");
        console2.logBytes(response);

        // Simulate successful miracle response ("1")
        vm.expectEmit(true, true, false, false);
        emit miracleAttempted(true, 2);

        vm.prank(address(mockFunctionsRouterSimple));
        gameplayEngineHelper.fulfillRequestHarness(requestId, response, "");

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
        ///////////// End fullfillRequest Sequence /////////////

        // Jailed prophet should now be free
        (, bool isTargetAlive, bool isTargetFree,) = phenomenon.getProphetData(2);
        assertTrue(isTargetFree);

        // And free
        assertTrue(isTargetAlive);

        // Number of players remaining should be 3
        assertEq(phenomenon.s_prophetsRemaining(), 3);
    }

    function testAccuseOfBlasphemyFail() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // User1 accuses user4 (prophet 3) of blasphemy
        vm.startPrank(user1);
        gameplayEngine.accuseOfBlasphemy(3);
        vm.stopPrank();

        ///////////// Start fullfillRequest Sequence /////////////
        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngineHelper));
        vm.stopPrank();

        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();
        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("4");
        console2.logBytes(response);

        // Simulate unsuccessful accusation response ("4")
        vm.expectEmit(true, false, false, false);
        emit accusation(false, true, 0, 3);

        vm.prank(address(mockFunctionsRouterSimple));
        gameplayEngineHelper.fulfillRequestHarness(requestId, response, "");

        vm.prank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
        ///////////// End fullfillRequest Sequence /////////////

        // Target prophet should be free
        (, bool isTargetAlive, bool isTargetFree,) = phenomenon.getProphetData(3);
        assertTrue(isTargetFree);

        // And still alive
        assertTrue(isTargetAlive);

        // Number of players remaining should be 3
        assertEq(phenomenon.s_prophetsRemaining(), 3);

        // Accuser should be jailed
        (,, bool isAccuserFree,) = phenomenon.getProphetData(0);
        assertFalse(isAccuserFree);
    }

    function testForceMiracle() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // Warp past the max interval
        vm.warp(block.timestamp + phenomenon.s_maxInterval() + 1);

        // Any user can force a miracle
        vm.startPrank(user2);
        gameplayEngine.forceMiracle();
        vm.stopPrank();

        // Game should be in AWAITING_RESPONSE state
        assertEq(uint256(phenomenon.gameStatus()), 2);

        // Get the requestId
        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();

        // Simulate successful miracle response
        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("1");
        (bool success,) = address(gameplayEngine).call(
            abi.encodeWithSignature("fulfillRequest(bytes32,bytes,bytes)", requestId, response, "")
        );
        assertTrue(success);

        // Game should be back to IN_PROGRESS
        assertEq(uint256(phenomenon.gameStatus()), 1);
    }

    function testGameStartProcessHighPriests() public {
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

        // Get the requestId
        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();

        // Simulate game start response where prophet 0 is high priest (not alive)
        // "0111" means prophet 0 is high priest, others are normal prophets
        vm.expectEmit(true, false, false, false);
        emit gameStarted(phenomenon.s_gameNumber());

        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("0111");
        (bool success,) = address(gameplayEngine).call(
            abi.encodeWithSignature("fulfillRequest(bytes32,bytes,bytes)", requestId, response, "")
        );
        assertTrue(success);

        // Check prophet 0 is now a high priest (not alive)
        (, bool isAlive,, uint256 args) = phenomenon.getProphetData(0);
        assertFalse(isAlive);
        assertEq(args, 99); // high priest arg

        // Game should be IN_PROGRESS
        assertEq(uint256(phenomenon.gameStatus()), 1);

        // Remaining prophets should be 3
        assertEq(phenomenon.s_prophetsRemaining(), 3);
    }

    function testRuleChecks() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // Try to perform action as wrong player
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSelector(GameplayEngine.Game__OutOfTurn.selector));
        gameplayEngine.performMiracle();
        vm.stopPrank();

        // Set game to PAUSED
        vm.startPrank(owner);
        phenomenon.ownerChangeGameState(Phenomenon.GameState.PAUSED);
        vm.stopPrank();

        // Try to perform action in wrong game state
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(GameplayEngine.Game__NotInProgress.selector));
        gameplayEngine.performMiracle();
        vm.stopPrank();

        // Reset game state
        vm.startPrank(owner);
        phenomenon.ownerChangeGameState(Phenomenon.GameState.IN_PROGRESS);
        vm.stopPrank();

        // Test minimum interval check
        vm.startPrank(user1);
        gameplayEngine.performMiracle();
        vm.stopPrank();

        // Process the request to advance turn
        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();
        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("1");
        (bool success,) = address(gameplayEngine).call(
            abi.encodeWithSignature("fulfillRequest(bytes32,bytes,bytes)", requestId, response, "")
        );
        assertTrue(success);

        // Get whose turn it is now
        uint256 currentTurn = phenomenon.getCurrentProphetTurn();
        address currentPlayer;
        (currentPlayer,,,) = phenomenon.getProphetData(currentTurn);

        // Try to perform action before min interval passes
        vm.prank(currentPlayer);
        vm.expectRevert(abi.encodeWithSelector(GameplayEngine.Game__MinimumTimeNotPassed.selector));
        gameplayEngine.performMiracle();

        // Warp past the min interval
        vm.warp(block.timestamp + phenomenon.s_minInterval() + 1);

        // Now should be able to perform action
        vm.prank(currentPlayer);
        gameplayEngine.performMiracle();

        // Game should be in AWAITING_RESPONSE state
        assertEq(uint256(phenomenon.gameStatus()), 2);
    }
}
