// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Phenomenon} from "./Phenomenon.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GameplayEngine
 * @author 0x-Omen.eth
 *
 * @notice This contract handles gameplay logic.
 * @dev This contract must be whitelisted on the Game contract to use the game
 * contract's Functions.
 */
contract GameplayEngine {
    error GameEng__NotOpen();
    error GameEng__Full();
    error GameEng__AlreadyRegistered();
    error GameEng__ProphetNumberError();

    //////////////////////// State Variables ////////////////////////
    Phenomenon private immutable i_gameContract;
    address private owner;

    event prophetEnteredGame(uint256 indexed prophetNumber, address indexed sender, uint256 indexed gameNumber);

    constructor(address _gameContract) {
        owner = msg.sender;
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
        uint256 numberOfProphets = i_gameContract.s_numberOfProphets;
        if (prophetsRegistered >= numberOfProphets) {
            revert GameEng__Full();
        }
        // Check that sender is not already registered
        uint256 gameNumber = i_gameContract.s_gameNumber;
        if (i_gameContract.prophetList(gameNumber, msg.sender)) {
            revert GameEng__AlreadyRegistered();
        }

        i_gameContract.registerProphet(msg.sender);
        uint256 entranceFee = i_gameContract.s_entranceFee;
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

        ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        uint256 s_randomnessSeed = uint256(blockhash(block.number - 1));
        i_gameContract.setRandomnessSeed(s_randomnessSeed);

        // semi-randomly select which prophet goes first
        i_gameContract.setCurrentProphetTurn(block.timestamp % numberOfProphets);
        // Check if prophet is chosenOne, if not then randomly assign to priest or prophet
        // Add Chainlink call here
        for (uint256 _prophet = 0; _prophet < s_numberOfProphets; _prophet++) {
            if (
                currentProphetTurn[s_gameNumber]
                    == (s_randomnessSeed / (42069420690990990091337 * encryptor)) % s_numberOfProphets
                    || ((uint256(blockhash(block.number - 1 - _prophet))) % 100) >= 15
            ) {
                // assign allegiance to self
                allegiance[s_gameNumber][prophets[_prophet].playerAddress] = _prophet;
                // give Prophet one of his own tickets
                ticketsToValhalla[s_gameNumber][prophets[_prophet].playerAddress] = 1;
                // Increment total tickets by 1
                s_totalTickets++;
                // This loop initializes acolytes[]
                // each loop pushes the number of acolytes/tickets sold into the prophet slot of the array
                highPriestsByProphet.push(1);
            } else {
                highPriestsByProphet.push(0);
                s_prophetsRemaining--;
                prophets[_prophet].isAlive = false;
                prophets[_prophet].args = 99;
            }
            acolytes.push(0);
        }
        turnManager();
        gameStatus = GameState.IN_PROGRESS;
        emit gameStarted(s_gameNumber);
    }

    // function ruleCheck()
    // function performMiracle()
    // function attemptSmite()
    // function accuseOfBlasphemy()

    // function reset() ???
    // function turnManager() ???
}
