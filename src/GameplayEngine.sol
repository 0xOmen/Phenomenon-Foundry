// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Phenomenon} from "./Phenomenon.sol";

/**
 * @title GameplayEngine
 * @author 0x-Omen.eth
 *
 * @notice This contract handles gameplay logic.
 * @dev This contract must be whitelisted on the Game contract to use the game
 * contract's Functions.
 */
contract GameplayEngine {
    //////////////////////// State Variables ////////////////////////
    Phenomenon private immutable i_gameContract;
    address private owner;

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
}
