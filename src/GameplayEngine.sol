// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Phenomenon} from "./Phenomenon.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FunctionsClient} from "@../../lib/chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@../../lib/chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@../../lib/chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

/**
 * @title GameplayEngine
 * @author 0x-Omen.eth
 *
 * @notice This contract handles gameplay logic.
 * @dev This contract must be whitelisted on the Game contract to use the game
 * contract's Functions.
 */
contract GameplayEngine is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    error GameEng__NotOpen();
    error GameEng__Full();
    error GameEng__AlreadyRegistered();
    error GameEng__ProphetNumberError();
    error Game__MinimumTimeNotPassed();
    error Game__NotInProgress();
    error Game__OutOfTurn();
    error Game__NotAllowed();
    error Game__ProphetNotFree();
    error UnexpectedRequestID(bytes32 requestId);

    //////////////////////// State Variables ////////////////////////
    Phenomenon private immutable i_gameContract;
    string[] args;

    bytes32 public s_lastFunctionRequestId;
    bytes public s_lastFunctionResponse;
    bytes public s_lastFunctionError;
    bytes encryptedSecretsUrls;
    uint8 donHostedSecretsSlotID;
    uint64 donHostedSecretsVersion;
    uint64 subscriptionId;
    address router = 0xf9B8fc078197181C841c296C876945aaa425B278; //Base Sepolia Chainlink Router
    string source;
    uint32 gasLimit = 750000;
    // Chainlink DON ID for Base Sepolia
    bytes32 donID = 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000;

    event prophetEnteredGame(uint256 indexed prophetNumber, address indexed sender, uint256 indexed gameNumber);
    event gameStarted(uint256 indexed gameNumber);
    event miracleAttempted(bool indexed isSuccess, uint256 indexed currentProphetTurn);
    event smiteAttempted(uint256 indexed target, bool indexed isSuccess, uint256 indexed currentProphetTurn);
    event accusation(
        bool indexed isSuccess, bool targetIsAlive, uint256 indexed currentProphetTurn, uint256 indexed _target
    );
    event Response(bytes32 indexed requestId, string character, bytes response, bytes err);

    constructor(address _gameContract, string memory _source, uint64 _subscriptionId)
        FunctionsClient(router)
        ConfirmedOwner(msg.sender)
    {
        source = _source;
        subscriptionId = _subscriptionId;
        i_gameContract = Phenomenon(_gameContract);
    }

    function enterGame() public {
        // Check that game is Open for registration
        uint256 gameStatus = uint256(i_gameContract.gameStatus());
        if (gameStatus != 0) {
            revert GameEng__NotOpen();
        }
        // Check that game is not full
        uint256 prophetsRegistered = i_gameContract.s_prophetsRemaining();
        uint256 numberOfProphets = i_gameContract.s_numberOfProphets();
        if (prophetsRegistered >= numberOfProphets) {
            revert GameEng__Full();
        }
        // Check that sender is not already registered
        uint256 gameNumber = i_gameContract.s_gameNumber();
        if (i_gameContract.prophetList(gameNumber, msg.sender)) {
            revert GameEng__AlreadyRegistered();
        }

        i_gameContract.registerProphet(msg.sender);
        uint256 entranceFee = i_gameContract.s_entranceFee();
        i_gameContract.increaseTokenDepositedThisGame(entranceFee);

        emit prophetEnteredGame(prophetsRegistered - 1, msg.sender, gameNumber);

        if ((prophetsRegistered + 1) == numberOfProphets) {
            startGame(prophetsRegistered, numberOfProphets);
        }

        IERC20(i_gameContract.getGameToken()).transferFrom(msg.sender, address(i_gameContract), entranceFee);
    }

    function startGame(uint256 prophetsRegistered, uint256 numberOfProphets) internal {
        /* Not needed if internal and only called from enterGame() as it is checked there
        if (gameStatus != 0) {
            revert Game__NotOpen();
        }
        */
        if (prophetsRegistered != numberOfProphets) {
            revert GameEng__ProphetNumberError();
        }

        // 1. Change gameStatus to IN_PROGRESS
        i_gameContract.changeGameStatus(1);

        // 2. Set randomnessSeed
        uint256 s_randomnessSeed = uint256(blockhash(block.number - 1));
        i_gameContract.setRandomnessSeed(s_randomnessSeed);

        // 3. semi-randomly select which prophet goes first
        i_gameContract.setProphetTurn(block.timestamp % numberOfProphets);
        // Check if prophet is chosenOne, if not then randomly assign to priest or prophet
        // Add Chainlink call here
        sendRequest(3);
    }

    function performMiracle() public {
        ruleCheck();
        sendRequest(0);
    }

    function forceMiracle() public {
        // Maximum time interval must have passed from last turn
        if (block.timestamp < i_gameContract.s_lastRoundTimestamp() + i_gameContract.s_maxInterval()) {
            revert Game__MinimumTimeNotPassed();
        }
        // Game must be in progress
        if (uint256(i_gameContract.gameStatus()) != 1) {
            revert Game__NotInProgress();
        }
        sendRequest(0);
    }

    function attemptSmite(uint256 _target) public {
        ruleCheck();
        (, bool targetIsAlive,,) = i_gameContract.getProphetData(_target);
        if (_target >= i_gameContract.s_numberOfProphets() || targetIsAlive == false) {
            revert Game__NotAllowed();
        }

        i_gameContract.updateProphetArgs(i_gameContract.getCurrentProphetTurn(), _target);
        sendRequest(1);
    }

    function accuseOfBlasphemy(uint256 _target) public {
        ruleCheck();
        (, bool targetIsAlive,,) = i_gameContract.getProphetData(_target);
        // Prophet to accuse must be alive and exist
        if (_target >= i_gameContract.s_numberOfProphets() || targetIsAlive == false) {
            revert Game__NotAllowed();
        }
        // Message Sender must be free prophet to accuse
        uint256 prophetNum = i_gameContract.getCurrentProphetTurn();
        (,, bool playerIsFree,) = i_gameContract.getProphetData(prophetNum);
        if (playerIsFree == false) {
            revert Game__ProphetNotFree();
        }
        i_gameContract.updateProphetArgs(i_gameContract.getCurrentProphetTurn(), _target);
        sendRequest(2);
    }

    function ruleCheck() internal view {
        // Minimum time interval must have passed from last turn
        if (block.timestamp < i_gameContract.s_lastRoundTimestamp() + i_gameContract.s_minInterval()) {
            revert Game__MinimumTimeNotPassed();
        }
        // Game must be in progress
        if (uint256(i_gameContract.gameStatus()) != 1) {
            revert Game__NotInProgress();
        }
        // Sending address must be their turn
        (address currentProphetAddress,,,) = i_gameContract.getProphetData(i_gameContract.getCurrentProphetTurn());
        if (msg.sender != currentProphetAddress) {
            revert Game__OutOfTurn();
        }
    }

    /**
     * @notice Used to set the arguments needed to send to Chainlink Function for offchain computation
     * @dev
     */
    function setArgs(uint256 _action) internal {
        delete args;
        uint256 currentProphetTurn = i_gameContract.getCurrentProphetTurn();
        args.push(Strings.toString(i_gameContract.getRandomnessSeed())); //roleVRFSeed
        args.push(Strings.toString(i_gameContract.s_numberOfProphets())); //Number_of_Prophets
        args.push(Strings.toString(_action)); //_action
        args.push(Strings.toString(currentProphetTurn)); //currentProphetTurn
        args.push(Strings.toString(i_gameContract.getTicketShare(currentProphetTurn))); //getTicketShare(currentProphetTurn)
    }

    function setSource(string memory _source) public onlyOwner {
        source = _source;
    }

    ///////////////////////////////////////////////////////////////////////////////////
    //////////////////       Functions to execute OffChain          ///////////////////
    ///////////////////////////////////////////////////////////////////////////////////

    function sendRequest(uint256 action) internal returns (bytes32 requestId) {
        //Need to figure out how to send encrypted secret!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        i_gameContract.changeGameStatus(2);
        setArgs(action);

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source); // Initialize the request with JS code
        if (encryptedSecretsUrls.length > 0) {
            req.addSecretsReference(encryptedSecretsUrls);
        } else if (donHostedSecretsVersion > 0) {
            req.addDONHostedSecrets(donHostedSecretsSlotID, donHostedSecretsVersion);
        }

        req.setArgs(args); // Set the arguments for the request

        // Send the request and store the request ID
        s_lastFunctionRequestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
        return s_lastFunctionRequestId;
    }

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        if (s_lastFunctionRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }
        s_lastFunctionResponse = response;
        s_lastFunctionError = err;

        //logic to change state of contract
        if (response.length == 1) {
            uint256 _currentProphetTurn = i_gameContract.getCurrentProphetTurn();
            //logic for unsuccessful miracle
            if (response[0] == "0") {
                // kill prophet
                i_gameContract.updateProphetLife(_currentProphetTurn, false);
                // decrease number of remaining prophets
                i_gameContract.updateProphetsRemaining(0, 1);
                emit miracleAttempted(false, _currentProphetTurn);
            }
            // Logic for successful miracle
            else if (response[0] == "1") {
                // if in jail, release from jail
                i_gameContract.updateProphetFreedom(_currentProphetTurn, true);
                emit miracleAttempted(true, _currentProphetTurn);
            }
            // Logic for an unsuccessful smite
            else if (response[0] == "2") {
                (,,, uint256 target) = i_gameContract.getProphetData(_currentProphetTurn);
                i_gameContract.updateProphetFreedom(_currentProphetTurn, false);
                emit smiteAttempted(target, false, _currentProphetTurn);
            }
            // Logic for a successful smite
            else if (response[0] == "3") {
                (,,, uint256 target) = i_gameContract.getProphetData(_currentProphetTurn);
                // Kill target Prophet
                i_gameContract.updateProphetLife(target, false);
                // Decrease number of remaining prophets by one
                i_gameContract.updateProphetsRemaining(0, 1);
                emit smiteAttempted(target, true, _currentProphetTurn);
            }
            // Logic for unsuccessful accusation
            else if (response[0] == "4") {
                (,,, uint256 target) = i_gameContract.getProphetData(_currentProphetTurn);
                // if in jail, release from jail
                i_gameContract.updateProphetFreedom(target, true);
                // put accuser in jail
                i_gameContract.updateProphetFreedom(_currentProphetTurn, false);
                emit accusation(false, true, _currentProphetTurn, target);
            }
            // Logic for successful accusation
            else if (response[0] == "5") {
                (,,, uint256 target) = i_gameContract.getProphetData(_currentProphetTurn);
                (,, bool targetIsFree,) = i_gameContract.getProphetData(target);
                if (targetIsFree) {
                    i_gameContract.updateProphetFreedom(target, false);
                    emit accusation(true, true, _currentProphetTurn, target);
                } else {
                    // Kill target Prophet
                    i_gameContract.updateProphetLife(target, false);
                    // Decrease number of remaining prophets by one
                    i_gameContract.updateProphetsRemaining(0, 1);
                    emit accusation(true, false, _currentProphetTurn, target);
                }
            }

            i_gameContract.turnManager();
        }
        // Only time more than one response is returned is at start game
        // This is the start game logic
        else if (response.length > 1) {
            for (uint256 _prophet = 0; _prophet < response.length; _prophet++) {
                if (response[_prophet] == "0") {
                    // Change prophet into High Priest
                    i_gameContract.decreaseAcolytes(_prophet, 1);
                    i_gameContract.updateProphetsRemaining(0, 1);
                    i_gameContract.updateProphetLife(_prophet, false);
                    i_gameContract.updateProphetArgs(_prophet, 99);
                } else {}
            }
            emit gameStarted(i_gameContract.s_gameNumber());
        }
        i_gameContract.changeGameStatus(1);
    }

    // function reset() ???
    // function turnManager() ???
}
