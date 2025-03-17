// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Phenomenon} from "./Phenomenon.sol";

/**
 * @title PhenomenonTicketEngine
 * @author 0x-Omen.eth
 *
 * @notice This contract will handle the buying and selling of ticketsToValhalla.
 * @dev This contract must be whitelisted on the Game contract to use the game
 * contract's Mint and Burn Functions.
 */
contract PhenomenonTicketEngine {
    //////////////////////// State Variables ////////////////////////
    Phenomenon private immutable i_gameContract;
    /// @dev This number is used to multiply the ticket cost allowing us to scale the ticket cost up or down.
    uint256 s_ticketMultiplier;
    address private owner;

    constructor(
        address _gameContract,
        uint256 _ticketMultiplier // 1000
    ) {
        owner = msg.sender;
        i_gameContract = Phenomenon(_gameContract);
        s_ticketMultiplier = _ticketMultiplier;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function changeOwner(address newOwner) public onlyOwner {
        owner = newOwner;
    }

    function setTicketMultiplier(uint256 _ticketMultiplier) external onlyOwner {
        s_ticketMultiplier = _ticketMultiplier;
    }
}
