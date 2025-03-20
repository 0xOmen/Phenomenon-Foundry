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
    error Game__ProphetIsDead();
    error Game__NotEnoughTicketsOwned();

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

    /**
     * @notice Use this to buy Tickets of a prophet. You can only own tickets of one prophet.
     * @notice In this version you cannot sell tickets, this could change in future versions.
     * @dev
     */
    function getReligion(uint256 _prophetNum, uint256 _ticketsToBuy) public {
        // Make sure game state allows for tickets to be bought
        uint256 gameStatus = uint256(i_gameContract.gameStatus());
        if (gameStatus != 1) {
            revert Game__NotInProgress();
        }
        // Prophets cannot buy tickets
        // the ability to 'buy' 0 tickets would allow changing of allegiance
        bool isSenderProphet = i_gameContract.checkProphetList(msg.sender);
        if (isSenderProphet || _ticketsToBuy == 0) {
            revert Game__NotAllowed();
        }
        // Can't buy tickets of dead or nonexistent prophets
        bool targetProphetAlive;
        (, targetProphetAlive,,) = getProphetData(_prophetNum);
        if (targetProphetAlive == false || _prophetNum >= i_gameContract.s_numberOfProphets()) {
            revert Game__ProphetIsDead();
        }

        // Cannot buy/sell  tickets if address eliminated (allegiant to prophet when that prophet is killed)
        // Addresses that own no tickets will default allegiance to 0 but 0 is a player number
        //  This causes issues with game logic so if allegiance is to 0
        //  we must also check if sending address owns tickets
        // If the address owns tickets then they truly have allegiance to player 0
        uint256 gameNumber = i_gameContract.s_gameNumber();
        uint256 senderTicketCount = i_gameContract.ticketsToValhalla(gameNumber, msg.sender);
        uint256 senderAllegiance = i_gameContract.allegiance(gameNumber, msg.sender);
        bool senderAllegianceAlive;
        (, senderAllegianceAlive,,) = getProphetData(senderAllegiance);
        if (senderAllegianceAlive == false && senderTicketCount != 0) {
            revert Game__AddressIsEliminated();
        }

        // Check if player owns any tickets of another prophet
        if (senderTicketCount != 0 && senderAllegiance != _prophetNum) {
            revert Game__NotAllowed();
        }

        uint256 totalPrice = getPrice(i_gameContract.accolites(_prophetNum), _ticketsToBuy);

        i_gameContract.increaseTicketsToValhalla(msg.sender, _ticketsToBuy);
        i_gameContract.increaseAccolites(_prophetNum, _ticketsToBuy);
        i_gameContract.increaseTotalTickets(_ticketsToBuy);
        i_gameContract.increaseTokenDepositedThisGame(totalPrice);
        i_gameContract.setPlayerAllegiance(msg.sender, _prophetNum);
        emit gainReligion(_prophetNum, _ticketsToBuy, totalPrice, msg.sender);

        //i_gameContract.depositGameTokens(msg.sender, totalPrice);
    }

    function loseReligion(uint256 _ticketsToSell) public {
        uint256 gameStatus = uint256(i_gameContract.gameStatus());
        if (gameStatus != 1) {
            revert Game__NotInProgress();
        }
        // Can't sell tickets of a dead prophet
        uint256 gameNumber = i_gameContract.s_gameNumber();
        uint256 currentAllegiance = i_gameContract.allegiance(gameNumber, msg.sender);
        bool targetProphetAlive;
        (, targetProphetAlive,,) = getProphetData(currentAllegiance);
        if (targetProphetAlive == false) {
            revert Game__ProphetIsDead();
        }
        // Prophets cannot sell tickets
        if (i_gameContract.prophetList(gameNumber, msg.sender)) {
            revert Game__NotAllowed();
        }
        // User cannot sell more tickets than they own
        uint256 startingUserTickets = i_gameContract.ticketsToValhalla(gameNumber, msg.sender);
        if (_ticketsToSell <= startingUserTickets && _ticketsToSell != 0) {
            // Get price of selling tickets
            uint256 totalPrice = getPrice(i_gameContract.accolites(currentAllegiance) - _ticketsToSell, _ticketsToSell);
            emit religionLost(currentAllegiance, _ticketsToSell, totalPrice, msg.sender);
            // Reduce the total number of tickets sold in the game by number of tickets sold by msg.sender
            i_gameContract.decreaseTotalTickets(_ticketsToSell);
            i_gameContract.decreaseAccolites(currentAllegiance, _ticketsToSell);
            // Remove tickets from msg.sender's balance
            i_gameContract.decreaseTicketsToValhalla(msg.sender, _ticketsToSell);
            // If msg.sender sold all tickets then set allegiance to 0
            if ((startingUserTickets - _ticketsToSell) == 0) {
                i_gameContract.setPlayerAllegiance(msg.sender, 0);
            }
            // Subtract the price of tickets sold from the s_tokensDepositedThisGame for this game
            i_gameContract.decreaseTokensDepositedThisGame(totalPrice);
            //Take 5% fee
            i_gameContract.applyProtocolFee((totalPrice * 5) / 100);
            totalPrice = (totalPrice * 95) / 100;

            i_gameContract.returnGameTokens(msg.sender, totalPrice);
        } else {
            revert Game__NotEnoughTicketsOwned();
        }
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

    // function loseReligion()
    // function redeem/claimTickets() ???
}
