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
        if (gameStatus != 1) {
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
            startGame();
        }

        IERC20(i_gameContract.GAME_TOKEN()).transferFrom(msg.sender, address(i_gameContract), entranceFee);
    }

    // function enterGame()
    // function startGame()
    // function ruleCheck()
    // function performMiracle()
    // function attemptSmite()
    // function accuseOfBlasphemy()

    // function reset() ???
    // function turnManager() ???
}
