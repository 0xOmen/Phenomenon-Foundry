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
    error UnexpectedRequestID(bytes32 requestId);

    //////////////////////// State Variables ////////////////////////
    Phenomenon private immutable i_gameContract;
    address private owner;
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
    event Response(bytes32 indexed requestId, string character, bytes response, bytes err);

    constructor(address _gameContract, string memory _source, uint64 _subscriptionId)
        FunctionsClient(router)
        ConfirmedOwner(msg.sender)
    {
        owner = msg.sender;
        source = _source;
        subscriptionId = _subscriptionId;
        i_gameContract = Phenomenon(_gameContract);
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function changeOwner(address newOwner) public onlyOwner {
        owner = newOwner;
    }

    function enterGame() public {
        // Check that game is Open for registration
        uint256 gameStatus = uint256(i_gameContract.gameStatus());
        if (gameStatus != 0) {
            revert GameEng__NotOpen();
        }
        // Check that game is not full
        uint256 prophetsRegistered = i_gameContract.prophets.length();
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

        IERC20(i_gameContract.GAME_TOKEN()).transferFrom(msg.sender, address(i_gameContract), entranceFee);
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
        i_gameContract.setCurrentProphetTurn(block.timestamp % numberOfProphets);
        // Check if prophet is chosenOne, if not then randomly assign to priest or prophet
        // Add Chainlink call here
        sendRequest(3);
    }

    /**
     * @notice Used to set the arguments needed to send to Chainlink Function for offchain computation
     * @dev
     */
    function setArgs(uint256 _action) internal {
        delete args;
        uint256 currentProphetTurn = i_gameContract.getCurrentProphetTurn();
        args.push(Strings.toString(i_gameContract.s_randomnessSeed())); //roleVRFSeed
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
            }
            // Logic for successful miracle
            else if (response[0] == "1") {
                // if in jail, release from jail
                i_gameContract.updateProphetFreedom(_currentProphetTurn, true);
            }
            // Logic for an unsuccessful smite
            else if (response[0] == "2") {}
            // Logic for a successful smite
            else if (response[0] == "3") {
                (,,, uint256 target) = i_gameContract.getProphetData(_currentProphetTurn);
                // Kill target Prophet
                i_gameContract.updateProphetLife(target, false);
                // Decrease number of remaining prophets by one
                i_gameContract.updateProphetsRemaining(0, 1);
            }
            // Logic for unsuccessful accusation
            else if (response[0] == "4") {
                (,,, uint256 target) = i_gameContract.getProphetData(_currentProphetTurn);
                // if in jail, release from jail
                i_gameContract.updateProphetFreedom(target, true);
            }
            // Logic for successful accusation
            else if (response[0] == "5") {
                (,,, uint256 target) = i_gameContract.getProphetData(_currentProphetTurn);
                (,, bool targetIsFree,) = i_gameContract.getProphetData(target);
                if (targetIsFree) {
                    i_gameContract.updateProphetFreedom(target, false);
                } else {
                    // Kill target Prophet
                    i_gameContract.updateProphetLife(target, false);
                    // Decrease number of remaining prophets by one
                    i_gameContract.updateProphetsRemaining(0, 1);
                }
            }
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
        }
        i_gameContract.changeGameStatus(1);
        turnManager();
    }

    // function ruleCheck()
    // function performMiracle()
    // function attemptSmite()
    // function accuseOfBlasphemy()

    // function reset() ???
    // function turnManager() ???
}
