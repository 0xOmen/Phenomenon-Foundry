// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Phenomenon} from "../src/Phenomenon.sol";
import {GameplayEngine} from "../src/GameplayEngine.sol";
import {PhenomenonTicketEngine} from "../src/PhenomenonTicketEngine.sol";
import {DeployPhenomenon} from "../script/DeployPhenomenon.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract PhenomenonTest is Test {
    Phenomenon public phenomenon;
    PhenomenonTicketEngine public phenomenonTicketEngine;
    GameplayEngine public gameplayEngine;
    HelperConfig public helperConfig;

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
    address public newGameplayEngine = address(7);
    address public newTicketEngine = address(8);
    address public nonOwner = address(9);
    address public newGameToken = address(10);

    // Events for testing
    event gameEnded(uint256 indexed gameNumber, uint256 indexed tokensPerTicket, uint256 indexed currentProphetTurn);
    event gameReset(uint256 indexed newGameNumber);
    event currentTurn(uint256 indexed nextProphetTurn);

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
        owner = phenomenon.getOwner();

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
        phenomenon.changeOwner(newOwner);
        vm.stopPrank();

        assertEq(phenomenon.getOwner(), newOwner);
    }

    function testNonOwnerCannotChangeOwner() public {
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Phenomenon.Game__OnlyOwner.selector));
        phenomenon.changeOwner(newOwner);
        vm.stopPrank();
    }

    function testOwnerCanChangeGameplayEngine() public {
        vm.startPrank(owner);
        phenomenon.changeGameplayEngine(newGameplayEngine);
        vm.stopPrank();
    }

    function testNonOwnerCannotChangeGameplayEngine() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Phenomenon.Game__OnlyOwner.selector));
        phenomenon.changeGameplayEngine(newGameplayEngine);
        vm.stopPrank();
    }

    function testOwnerCanChangeTicketEngine() public {
        vm.startPrank(owner);
        phenomenon.changeTicketEngine(newTicketEngine);
        vm.stopPrank();
    }

    function testOwnerCanChangeGameToken() public {
        vm.startPrank(owner);
        phenomenon.changeGameToken(newGameToken);
        vm.stopPrank();

        assertEq(phenomenon.getGameToken(), newGameToken);
    }

    function testOwnerCanChangeEntryFee() public {
        uint256 newFee = 20 ether;
        vm.startPrank(owner);
        phenomenon.changeEntryFee(newFee);
        vm.stopPrank();

        assertEq(phenomenon.s_entranceFee(), newFee);
    }

    function testOwnerCanSetProtocolFee() public {
        uint256 newFee = 1000; // 10%
        vm.startPrank(owner);
        phenomenon.setProtocolFee(newFee);
        vm.stopPrank();

        assertEq(phenomenon.s_protocolFee(), newFee);
    }

    function testCannotSetProtocolFeeTooHigh() public {
        uint256 invalidFee = 10001; // More than 100%
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(Phenomenon.Game__ProtocolFeeTooHigh.selector));
        phenomenon.setProtocolFee(invalidFee);
        vm.stopPrank();
    }

    function testOwnerCanSetMaxInterval() public {
        uint256 newInterval = 300; // 5 minutes
        vm.startPrank(owner);
        phenomenon.setMaxInterval(newInterval);
        vm.stopPrank();

        assertEq(phenomenon.s_maxInterval(), newInterval);
    }

    function testOwnerCanSetMinInterval() public {
        uint256 newInterval = 60; // 1 minute
        vm.startPrank(owner);
        phenomenon.setMinInterval(newInterval);
        vm.stopPrank();

        assertEq(phenomenon.s_minInterval(), newInterval);
    }

    /*//////////////////////////////////////////////////////////////
                       GAME STATE TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnerCanChangeGameState() public {
        vm.startPrank(owner);
        phenomenon.ownerChangeGameState(Phenomenon.GameState.PAUSED);
        vm.stopPrank();

        assertEq(uint256(phenomenon.gameStatus()), uint256(Phenomenon.GameState.PAUSED));
    }

    function testResetGameIncrementsGameNumber() public {
        uint256 initialGameNumber = phenomenon.s_gameNumber();

        vm.startPrank(owner);
        phenomenon.reset(4); // Reset with 4 prophets
        vm.stopPrank();

        assertEq(phenomenon.s_gameNumber(), initialGameNumber + 1);
    }

    function testResetGameVerifyState() public {
        vm.startPrank(owner);
        phenomenon.reset(5); // Reset with 5 prophets
        vm.stopPrank();

        assertEq(phenomenon.s_tokensDepositedThisGame(), 0);
        assertEq(phenomenon.s_prophetsRemaining(), 0);
        assertEq(phenomenon.s_numberOfProphets(), 5);
        assertEq(phenomenon.s_totalTickets(), 0);
        assertEq(uint256(phenomenon.gameStatus()), uint256(Phenomenon.GameState.OPEN));
    }

    function testResetGameEmitsEvent() public {
        uint256 nextGameNumber = phenomenon.s_gameNumber() + 1;

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false);
        emit gameReset(nextGameNumber);
        phenomenon.reset(4);
        vm.stopPrank();
    }

    function testResetGameValidation() public {
        // Test invalid number of prophets (less than 4)
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(Phenomenon.Game__ProphetNumberError.selector));
        phenomenon.reset(3);
        vm.stopPrank();

        // Test invalid number of prophets (more than 9)
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(Phenomenon.Game__ProphetNumberError.selector));
        phenomenon.reset(10);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       PROPHET REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegisterProphet() public {
        // Mock the gameplay engine calling registerProphet
        vm.startPrank(address(gameplayEngine));

        // Approve tokens from user1 for the registration
        vm.stopPrank();
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        // Register prophet
        vm.startPrank(address(gameplayEngine));
        phenomenon.registerProphet(user1);
        vm.stopPrank();

        // Verify registration
        bool isRegistered = phenomenon.prophetList(phenomenon.s_gameNumber(), user1);
        assertEq(isRegistered, true);
        assertEq(phenomenon.s_prophetsRemaining(), 1);

        // Verify prophet data
        (address prophetAddress, bool isAlive, bool isFree,) = phenomenon.getProphetData(0);
        assertEq(prophetAddress, user1);
        assertEq(isAlive, true);
        assertEq(isFree, true);

        // Verify token transfer
        assertEq(phenomenon.s_tokensDepositedThisGame(), phenomenon.s_entranceFee());
    }

    function testOnlyGameplayEngineCanRegisterProphet() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Phenomenon.Game__OnlyController.selector));
        phenomenon.registerProphet(user1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       PROPHET MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateProphetLife() public {
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        vm.startPrank(address(gameplayEngine));
        phenomenon.registerProphet(user1);

        // Update prophet life
        phenomenon.updateProphetLife(0, false);
        vm.stopPrank();

        // Verify update
        (, bool isAlive,,) = phenomenon.getProphetData(0);
        assertEq(isAlive, false);
    }

    function testUpdateProphetFreedom() public {
        vm.startPrank(address(gameplayEngine));
        phenomenon.registerProphet(user1);

        // Update prophet freedom
        phenomenon.updateProphetFreedom(0, false);
        vm.stopPrank();

        // Verify update
        (,, bool isFree,) = phenomenon.getProphetData(0);
        assertEq(isFree, false);
    }

    function testUpdateProphetArgs() public {
        uint256 newArgs = 123;
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        vm.startPrank(address(gameplayEngine));
        phenomenon.registerProphet(user1);

        // Update prophet args
        phenomenon.updateProphetArgs(0, newArgs);
        vm.stopPrank();

        // Verify update
        (,,, uint256 args) = phenomenon.getProphetData(0);
        assertEq(args, newArgs);
    }

    /*//////////////////////////////////////////////////////////////
                       TURN MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetProphetTurn() public {
        uint256 prophetNum = 2;

        vm.startPrank(address(gameplayEngine));
        phenomenon.setProphetTurn(prophetNum);
        vm.stopPrank();

        assertEq(phenomenon.getCurrentProphetTurn(), prophetNum);
    }

    function testTurnManagerWithOneProphetRemaining() public {
        uint256 tokensPerTicket = (4 * phenomenon.s_entranceFee() * (10000 - phenomenon.s_protocolFee())) / 10000;
        // Set up game with 4 prophets
        vm.startPrank(owner);
        phenomenon.reset(4);
        vm.stopPrank();

        // Register 4 prophets
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        vm.startPrank(user3);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        vm.startPrank(user4);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        // Register prophets
        vm.startPrank(address(gameplayEngine));
        phenomenon.registerProphet(user1);
        phenomenon.registerProphet(user2);
        phenomenon.registerProphet(user3);
        phenomenon.registerProphet(user4);

        // Set game in progress
        phenomenon.changeGameStatus(1);

        // Kill prophets 1, 2, and 3
        phenomenon.updateProphetLife(0, false);
        phenomenon.updateProphetLife(1, false);
        phenomenon.updateProphetLife(2, false);
        phenomenon.updateProphetsRemaining(0, 3);

        // Now only prophet 3 (index 3) remains alive
        assertEq(phenomenon.s_prophetsRemaining(), 1);

        // Set current turn to prophet 2 (index 2)
        phenomenon.setProphetTurn(2);

        vm.expectEmit(true, false, false, false);
        emit currentTurn(3);
        // Execute turn manager which should end the game and set turn to prophet 3
        vm.expectEmit(true, true, true, false);
        emit gameEnded(phenomenon.s_gameNumber(), tokensPerTicket, 3); // game number, tokens per ticket (4 * entrance fee), current prophet turn (3)

        phenomenon.turnManager();
        vm.stopPrank();

        // Verify game ended
        assertEq(uint256(phenomenon.gameStatus()), uint256(Phenomenon.GameState.ENDED));

        // Verify turn was set to the last remaining prophet
        assertEq(phenomenon.getCurrentProphetTurn(), 3);
    }

    function testTurnManagerNextTurn() public {
        // Set up game with 4 prophets
        vm.startPrank(owner);
        phenomenon.reset(4);
        vm.stopPrank();

        // Register 4 prophets
        vm.startPrank(address(gameplayEngine));

        // First approve from each user
        vm.stopPrank();
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        vm.startPrank(user3);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        vm.startPrank(user4);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        // Register prophets
        vm.startPrank(address(gameplayEngine));
        phenomenon.registerProphet(user1);
        phenomenon.registerProphet(user2);
        phenomenon.registerProphet(user3);
        phenomenon.registerProphet(user4);

        // Set game in progress
        phenomenon.changeGameStatus(1);

        // Kill prophet 1 (index 0)
        phenomenon.updateProphetLife(0, false);
        phenomenon.updateProphetsRemaining(0, 1);

        // Now we have 3 prophets remaining
        assertEq(phenomenon.s_prophetsRemaining(), 3);

        // Set current turn to prophet 4 (index 3)
        phenomenon.setProphetTurn(3);

        // Execute turn manager which should advance turn to prophet 2 (index 1)
        // (skipping prophet 1 who is dead)
        vm.expectEmit(true, false, false, false);
        emit currentTurn(1);

        phenomenon.turnManager();
        vm.stopPrank();

        // Verify turn was advanced
        assertEq(phenomenon.getCurrentProphetTurn(), 1);

        // Verify game still in progress
        assertEq(uint256(phenomenon.gameStatus()), uint256(Phenomenon.GameState.IN_PROGRESS));
    }

    function testEnterGame() public {
        vm.startPrank(address(user1));
        ERC20Mock(weth).approve(address(phenomenon), 1000 ether);
        gameplayEngine.enterGame(new bytes32[](0));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       TOKEN MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnerTokenTransfer() public {
        uint256 amount = 10 ether;

        // Mint tokens directly to the contract
        ERC20Mock(weth).mint(address(phenomenon), amount);

        // Update owner balance in the contract
        vm.startPrank(address(phenomenonTicketEngine));
        phenomenon.applyProtocolFee(amount);
        vm.stopPrank();

        // Now owner can transfer tokens
        vm.startPrank(owner);
        phenomenon.transferOwnerTokens(amount, owner);
        vm.stopPrank();

        // Verify transfer
        assertEq(ERC20Mock(weth).balanceOf(owner), amount);
        assertEq(phenomenon.getOwnerTokenBalance(), 0);
    }

    function testCannotTransferMoreThanOwnerBalance() public {
        uint256 ownerBalance = phenomenon.getOwnerTokenBalance();
        uint256 amount = ownerBalance + 1 ether;

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(Phenomenon.Game__NotEnoughTicketsOwned.selector));
        phenomenon.transferOwnerTokens(amount, owner);
        vm.stopPrank();
    }

    function testDepositGameTokens() public {
        uint256 amount = 50 ether;

        // Setup - user1 approves tokens
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), amount);
        vm.stopPrank();

        // Initial balance
        uint256 initialContractBalance = ERC20Mock(weth).balanceOf(address(phenomenon));
        uint256 initialUser1Balance = ERC20Mock(weth).balanceOf(user1);

        // Deposit tokens
        vm.startPrank(address(phenomenonTicketEngine));
        phenomenon.depositGameTokens(user1, amount);
        vm.stopPrank();

        // Verify balances
        assertEq(ERC20Mock(weth).balanceOf(address(phenomenon)), initialContractBalance + amount);
        assertEq(ERC20Mock(weth).balanceOf(user1), initialUser1Balance - amount);
    }

    function testReturnGameTokens() public {
        uint256 amount = 25 ether;

        // Setup - mint tokens directly to the contract
        ERC20Mock(weth).mint(address(phenomenon), amount);

        uint256 initialContractBalance = ERC20Mock(weth).balanceOf(address(phenomenon));
        uint256 initialUser1Balance = ERC20Mock(weth).balanceOf(user1);

        // Return tokens
        vm.startPrank(address(phenomenonTicketEngine));
        phenomenon.returnGameTokens(user1, amount);
        vm.stopPrank();

        // Verify balances
        assertEq(ERC20Mock(weth).balanceOf(address(phenomenon)), initialContractBalance - amount);
        assertEq(ERC20Mock(weth).balanceOf(user1), initialUser1Balance + amount);
    }

    function testOwnerTokenTransferAnyToken() public {
        // Create a different token for testing
        ERC20Mock differentToken = new ERC20Mock();
        uint256 amount = 15 ether;

        // Mint tokens directly to the phenomenon contract
        differentToken.mint(address(phenomenon), amount);

        // Owner can transfer any token from the contract
        vm.startPrank(owner);
        phenomenon.ownerTokenTransfer(amount, address(differentToken), owner);
        vm.stopPrank();

        // Verify the balance
        assertEq(differentToken.balanceOf(owner), amount);
        assertEq(differentToken.balanceOf(address(phenomenon)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                       TICKET ENGINE TESTS
    //////////////////////////////////////////////////////////////*/

    function testIncreaseTotalTickets() public {
        uint256 amount = 5;
        uint256 initialTickets = phenomenon.s_totalTickets();

        vm.startPrank(address(phenomenonTicketEngine));
        phenomenon.increaseTotalTickets(amount);
        vm.stopPrank();

        assertEq(phenomenon.s_totalTickets(), initialTickets + amount);
    }

    function testDecreaseTotalTickets() public {
        // First increase tickets
        uint256 amount = 5;

        vm.startPrank(address(phenomenonTicketEngine));
        phenomenon.increaseTotalTickets(amount);
        uint256 currentTickets = phenomenon.s_totalTickets();

        // Then decrease tickets
        phenomenon.decreaseTotalTickets(2);
        vm.stopPrank();

        assertEq(phenomenon.s_totalTickets(), currentTickets - 2);
    }

    function testIncreaseTokensDepositedThisGame() public {
        uint256 amount = 10 ether;
        uint256 initialDeposit = phenomenon.s_tokensDepositedThisGame();

        vm.startPrank(address(phenomenonTicketEngine));
        phenomenon.increaseTokenDepositedThisGame(amount);
        vm.stopPrank();

        assertEq(phenomenon.s_tokensDepositedThisGame(), initialDeposit + amount);
    }

    function testDecreaseTokensDepositedThisGame() public {
        // First increase deposits
        uint256 amount = 10 ether;

        vm.startPrank(address(phenomenonTicketEngine));
        phenomenon.increaseTokenDepositedThisGame(amount);
        uint256 currentDeposit = phenomenon.s_tokensDepositedThisGame();

        // Then decrease deposits
        phenomenon.decreaseTokensDepositedThisGame(5 ether);
        vm.stopPrank();

        assertEq(phenomenon.s_tokensDepositedThisGame(), currentDeposit - 5 ether);
    }

    function testSetPlayerAllegiance() public {
        uint256 gameNumber = phenomenon.s_gameNumber();
        uint256 target = 3;

        vm.startPrank(address(phenomenonTicketEngine));
        phenomenon.setPlayerAllegiance(user1, target);
        vm.stopPrank();

        assertEq(phenomenon.allegiance(gameNumber, user1), target);
    }

    function testGetTicketShare() public {
        // Set up game
        vm.startPrank(owner);
        phenomenon.reset(4);
        vm.stopPrank();

        // Register a prophet
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        // Register prophet
        vm.startPrank(address(gameplayEngine));
        phenomenon.registerProphet(user1);
        vm.stopPrank();

        // Add more tickets to prophet 0
        vm.startPrank(address(phenomenonTicketEngine));
        phenomenon.increaseAcolytes(0, 9); // Prophet now has 10 tickets (1 default + 9 new)
        phenomenon.increaseTotalTickets(9); // Total tickets increased from 1 to 10
        vm.stopPrank();

        // Get ticket share - should be 100% as there's only one prophet with tickets
        assertEq(phenomenon.getTicketShare(0), 100);

        // Register second prophet
        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        vm.startPrank(address(gameplayEngine));
        phenomenon.registerProphet(user2);
        vm.stopPrank();

        // First prophet should have 10/11 tickets (~91%)
        // Second prophet should have 1/11 tickets (~9%)
        assertEq(phenomenon.getTicketShare(0), 90); // rounds down to 90%
        assertEq(phenomenon.getTicketShare(1), 9); // rounds down to 9%
    }

    function testIncreaseDecreaseAcolytes() public {
        // Set up game
        vm.startPrank(owner);
        phenomenon.reset(4);
        vm.stopPrank();

        // Register prophet
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(phenomenon), phenomenon.s_entranceFee());
        vm.stopPrank();

        vm.startPrank(address(gameplayEngine));
        phenomenon.registerProphet(user1);

        // Increase acolytes
        phenomenon.increaseAcolytes(0, 5);

        // Verify
        assertEq(phenomenon.acolytes(0), 6); // 1 initial + 5 more

        // Decrease acolytes
        phenomenon.decreaseAcolytes(0, 2);

        // Verify
        assertEq(phenomenon.acolytes(0), 4); // 6 - 2
        vm.stopPrank();
    }

    function testIncreaseDecreaseTicketsToValhalla() public {
        uint256 gameNumber = phenomenon.s_gameNumber();

        vm.startPrank(address(phenomenonTicketEngine));

        // Increase tickets
        phenomenon.increaseTicketsToValhalla(user1, 10);

        // Verify
        assertEq(phenomenon.ticketsToValhalla(gameNumber, user1), 10);

        // Decrease tickets
        phenomenon.decreaseTicketsToValhalla(user1, 3);

        // Verify
        assertEq(phenomenon.ticketsToValhalla(gameNumber, user1), 7);
        vm.stopPrank();
    }

    function testIncreaseDecreaseHighPriest() public {
        vm.startPrank(address(phenomenonTicketEngine));

        // Increase high priests
        phenomenon.increaseHighPriest(1); // Prophet 1 gets a high priest

        // Verify (initial value is 0)
        assertEq(phenomenon.highPriestsByProphet(1), 1);

        // Increase again
        phenomenon.increaseHighPriest(1);

        // Verify
        assertEq(phenomenon.highPriestsByProphet(1), 2);

        // Decrease high priests
        phenomenon.decreaseHighPriest(1);

        // Verify
        assertEq(phenomenon.highPriestsByProphet(1), 1);
        vm.stopPrank();
    }
}
