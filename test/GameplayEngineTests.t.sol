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

contract GameplayEngineTests is Test {
    GameplayEngine public gameplayEngine;
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

        // Expect the gameStarted event
        vm.expectEmit(true, false, false, false);
        emit gameStarted(phenomenon.s_gameNumber());

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

        // Simulate the game start response from Chainlink
        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();

        // Manually set game status to IN_PROGRESS to simulate response from Chainlink

        //  ******** Do we really need to set this? it should get done automatically*********
        vm.startPrank(owner);
        phenomenon.ownerChangeGameState(Phenomenon.GameState.IN_PROGRESS);
        vm.stopPrank();
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

        // Get the requestId
        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();

        // Simulate successful miracle response ("1")
        vm.expectEmit(true, false, false, false);
        emit miracleAttempted(true, 0);

        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("1");
        (bool success,) = address(gameplayEngine).call(
            abi.encodeWithSignature("fulfillRequest(bytes32,bytes,bytes)", requestId, response, "")
        );
        assertTrue(success);

        // Prophet should still be alive and free
        (, bool isAlive, bool isFree,) = phenomenon.getProphetData(0);
        assertTrue(isAlive);
        assertTrue(isFree);

        // Game should be back to IN_PROGRESS
        assertEq(uint256(phenomenon.gameStatus()), 1);
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

        // Get the requestId
        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();

        // Simulate failed miracle response ("0")
        vm.expectEmit(true, false, false, false);
        emit miracleAttempted(false, 0);

        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("0");
        (bool success,) = address(gameplayEngine).call(
            abi.encodeWithSignature("fulfillRequest(bytes32,bytes,bytes)", requestId, response, "")
        );
        assertTrue(success);

        // Prophet should be dead
        (, bool isAlive,,) = phenomenon.getProphetData(0);
        assertFalse(isAlive);

        // Prophets remaining should be reduced by 1
        assertEq(phenomenon.s_prophetsRemaining(), 3);
    }

    function testAttemptSmiteSuccess() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // User1 attempts to smite user2 (prophet 1)
        vm.startPrank(user1);
        gameplayEngine.attemptSmite(1);
        vm.stopPrank();

        // Get the requestId
        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();

        // Simulate successful smite response ("3")
        vm.expectEmit(true, false, false, false);
        emit smiteAttempted(1, true, 0);

        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("3");
        (bool success,) = address(gameplayEngine).call(
            abi.encodeWithSignature("fulfillRequest(bytes32,bytes,bytes)", requestId, response, "")
        );
        assertTrue(success);

        // Target prophet should be dead
        (, bool isTargetAlive,,) = phenomenon.getProphetData(1);
        assertFalse(isTargetAlive);

        // Prophets remaining should be reduced by 1
        assertEq(phenomenon.s_prophetsRemaining(), 3);
    }

    function testAttemptSmiteFail() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // User1 attempts to smite user2 (prophet 1)
        vm.startPrank(user1);
        gameplayEngine.attemptSmite(1);
        vm.stopPrank();

        // Get the requestId
        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();

        // Simulate failed smite response ("2")
        vm.expectEmit(true, false, false, false);
        emit smiteAttempted(1, false, 0);

        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("2");
        (bool success,) = address(gameplayEngine).call(
            abi.encodeWithSignature("fulfillRequest(bytes32,bytes,bytes)", requestId, response, "")
        );
        assertTrue(success);

        // Attacker should be jailed
        (,, bool isAttackerFree,) = phenomenon.getProphetData(0);
        assertFalse(isAttackerFree);

        // Target prophet should still be alive
        (, bool isTargetAlive,,) = phenomenon.getProphetData(1);
        assertTrue(isTargetAlive);
    }

    function testAccuseOfBlasphemySuccess() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // User1 accuses user2 (prophet 1) of blasphemy
        vm.startPrank(user1);
        gameplayEngine.accuseOfBlasphemy(1);
        vm.stopPrank();

        // Get the requestId
        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();

        // Simulate successful accusation response ("5")
        vm.expectEmit(true, false, false, false);
        emit accusation(true, true, 0, 1);

        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("5");
        (bool success,) = address(gameplayEngine).call(
            abi.encodeWithSignature("fulfillRequest(bytes32,bytes,bytes)", requestId, response, "")
        );
        assertTrue(success);

        // Target prophet should be jailed
        (,, bool isTargetFree,) = phenomenon.getProphetData(1);
        assertFalse(isTargetFree);

        // But still alive
        (, bool isTargetAlive,,) = phenomenon.getProphetData(1);
        assertTrue(isTargetAlive);
    }

    function testAccuseOfBlasphemyFail() public {
        setupGameWithFourProphets();

        // Set prophet 0 (user1) as the current turn
        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(0);
        vm.stopPrank();

        // User1 accuses user2 (prophet 1) of blasphemy
        vm.startPrank(user1);
        gameplayEngine.accuseOfBlasphemy(1);
        vm.stopPrank();

        // Get the requestId
        bytes32 requestId = gameplayEngine.s_lastFunctionRequestId();

        // Simulate failed accusation response ("4")
        vm.expectEmit(true, false, false, false);
        emit accusation(false, true, 0, 1);

        bytes memory response = mockFunctionsRouterSimple._fulfillRequest("4");
        (bool success,) = address(gameplayEngine).call(
            abi.encodeWithSignature("fulfillRequest(bytes32,bytes,bytes)", requestId, response, "")
        );
        assertTrue(success);

        // Target prophet should still be free
        (,, bool isTargetFree,) = phenomenon.getProphetData(1);
        assertTrue(isTargetFree);

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
