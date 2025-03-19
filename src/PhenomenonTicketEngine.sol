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
    error Game__NotAllowed();
    error Game__NotInProgress();
    error Game__AddressIsEliminated();

    struct ProphetData {
        address playerAddress;
        bool isAlive;
        bool isFree;
        uint256 args;
    }
    //////////////////////// State Variables ////////////////////////

    Phenomenon private immutable i_gameContract;
    /// @dev This number is used to multiply the ticket cost allowing us to scale the ticket cost up or down.
    uint256 s_ticketMultiplier;
    address private owner;

    event religionLost(
        uint256 indexed _target, uint256 indexed numTicketsSold, uint256 indexed totalPrice, address sender
    );
    event gainReligion(
        uint256 indexed _target, uint256 indexed numTicketsBought, uint256 indexed totalPrice, address sender
    );

    constructor(
        address gameContractAddress,
        uint256 ticketMultiplier // 1000
    ) {
        owner = msg.sender;
        i_gameContract = Phenomenon(gameContractAddress);
        s_ticketMultiplier = ticketMultiplier;
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

    function highPriest(uint256 _senderProphetNum, uint256 _target) public {
        // Only prophets can call this function
        // Prophet must be alive or assigned to high priest
        // Can't try to follow non-existent prophet
        // Can't call if <= 2 prophets remain
        address senderProphetAddress;
        bool senderProphetAlive;
        uint256 senderProphetArgs;
        (senderProphetAddress, senderProphetAlive,, senderProphetArgs) = getProphetData(_senderProphetNum);

        uint256 gameNumber = i_gameContract.s_gameNumber();
        if (
            // Only a prophet can call this function
            // Prophet must be alive or a High Priest (priests are "killed" at game start)
            // Target must exist
            // Must have more than 2 prophets alive
            senderProphetAddress != msg.sender || (!senderProphetAlive && senderProphetArgs != 99)
                || _target >= i_gameContract.s_numberOfProphets() || i_gameContract.s_prophetsRemaining() <= 2
        ) {
            revert Game__NotAllowed();
        }
        uint256 senderAllegiance = i_gameContract.allegiance(gameNumber, msg.sender);
        bool currentLeaderAlive;
        (, currentLeaderAlive,,) = getProphetData(senderAllegiance);
        // Can't change allegiance if following an eliminated prophet
        if (currentLeaderAlive == false) {
            // Allegiance automatically set to 0? Maybe set to self?
            uint256 prophetZeroArgs;
            (,,, prophetZeroArgs) = getProphetData(0);
            if (senderAllegiance != 0 || (senderAllegiance == 0 && prophetZeroArgs != 99)) {
                revert Game__AddressIsEliminated();
            }
        }
        // Check if gameStaus is IN_PROGRESS or 1
        uint256 gameStatus = uint256(i_gameContract.gameStatus());
        if (gameStatus != 1) {
            revert Game__NotInProgress();
        }
        // High Priests are not given a TicketToValhalla at game start
        uint256 ticketstoValhalla = i_gameContract.ticketsToValhalla(gameNumber, msg.sender);
        if (ticketstoValhalla > 0) {
            emit religionLost(_target, 1, 0, msg.sender);
            i_gameContract.decreaseHighPriest(senderAllegiance);
            i_gameContract.decreaseTicketsToValhalla(msg.sender, 1);
            i_gameContract.decreaseTotalTickets(1);
        }
        emit gainReligion(_target, 1, 0, msg.sender);
        i_gameContract.increaseHighPriest(_target);
        i_gameContract.increaseTicketsToValhalla(msg.sender, 1);
        i_gameContract.setPlayerAllegiance(msg.sender, _target);
        i_gameContract.increaseTotalTickets(1);
    }

    function getPrice(uint256 supply, uint256 amount) public view returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : ((supply) * (1 + supply) * (2 * (supply) + 1)) / 6;
        uint256 sum2 =
            (((1 + supply) + amount - 1) * ((1 + supply) + amount) * (2 * ((1 + supply) + amount - 1) + 1)) / 6;
        uint256 summation = sum2 - sum1;
        return (((summation * 1 ether) * s_ticketMultiplier) / 2);
    }

    function getProphetData(uint256 prophetNum) public view returns (address, bool, bool, uint256) {
        return i_gameContract.getProphetData(prophetNum);
    }

    // function getPrice() ??? or just call from the game contract?
    // function getReligion()
    // function loseReligion()
    // function redeem/claimTickets() ???
}
