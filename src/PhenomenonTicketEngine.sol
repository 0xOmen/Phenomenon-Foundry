// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Phenomenon} from "./Phenomenon.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PhenomenonTicketEngine
 * @author 0x-Omen.eth
 *
 * @notice This contract will handle the buying and selling of ticketsToValhalla.
 * @dev This contract must be whitelisted on the Game contract to use the game
 * contract's Mint and Burn Functions.
 */
contract PhenomenonTicketEngine is ReentrancyGuard {
    error TicketEng__NotAllowed();
    error TicketEng__NotInProgress();
    error TicketEng__AddressIsEliminated();
    error TicketEng__ProphetIsDead();
    error TicketEng__NotEnoughTicketsOwned();

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
    event ticketsClaimed(address indexed player, uint256 indexed tokensSent, uint256 indexed gameNumber);

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

    /**
     * @notice This function allows a prophet to change their allegiance.
     * @dev This function can only be called if the game is in progress.
     * @dev This function can only be called by a prophet.
     * @param _senderProphetNum The number of the prophet to change allegiance to.
     * @param _target The number of the prophet to change allegiance to.
     */
    function highPriest(uint256 _senderProphetNum, uint256 _target) public {
        address senderProphetAddress;
        bool senderProphetAlive;
        uint256 senderProphetArgs;
        (senderProphetAddress, senderProphetAlive,, senderProphetArgs) = getProphetData(_senderProphetNum);
        (, bool targetIsAlive,,) = getProphetData(_target);
        uint256 gameNumber = i_gameContract.s_gameNumber();
        if (
            // Only a prophet can call this function
            // Prophet must be alive or a High Priest (priests are "killed" at game start)
            // Target must exist and be alive
            // Must have more than 2 prophets alive
            senderProphetAddress != msg.sender || (!senderProphetAlive && senderProphetArgs != 99)
                || _target >= i_gameContract.s_numberOfProphets() || !targetIsAlive
                || i_gameContract.s_prophetsRemaining() <= 2
        ) {
            revert TicketEng__NotAllowed();
        }
        uint256 senderAllegiance = i_gameContract.allegiance(gameNumber, msg.sender);
        bool currentLeaderAlive;
        (, currentLeaderAlive,,) = getProphetData(senderAllegiance);
        // Can't change allegiance if following an eliminated prophet
        if (currentLeaderAlive == false) {
            // Allegiance automatically set to self?
            if ((senderProphetArgs != 99 && senderAllegiance != _senderProphetNum)) {
                revert TicketEng__AddressIsEliminated();
            }
        }
        // Check if gameStaus is IN_PROGRESS or 1
        uint256 gameStatus = uint256(i_gameContract.gameStatus());
        if (gameStatus != 1) {
            revert TicketEng__NotInProgress();
        }

        emit religionLost(_target, 1, 0, msg.sender);
        i_gameContract.decreaseHighPriest(senderAllegiance);

        emit gainReligion(_target, 1, 0, msg.sender);
        i_gameContract.increaseHighPriest(_target);
        i_gameContract.setPlayerAllegiance(msg.sender, _target);
    }

    /**
     * @notice Use this to buy Tickets of a prophet. You can only own tickets of one prophet.
     * @dev This function can only be called if the game is in progress.
     * @dev This function can only be called by a non-prophet.
     * @param _prophetNum The number of the prophet to buy tickets of.
     * @param _ticketsToBuy The number of tickets to buy.
     */
    function getReligion(uint256 _prophetNum, uint256 _ticketsToBuy) public nonReentrant {
        // Make sure game state allows for tickets to be bought
        uint256 gameStatus = uint256(i_gameContract.gameStatus());
        if (gameStatus != 1) {
            revert TicketEng__NotInProgress();
        }
        // Prophets cannot buy tickets
        // the ability to 'buy' 0 tickets would allow changing of allegiance
        bool isSenderProphet = i_gameContract.checkProphetList(msg.sender);
        if (isSenderProphet || _ticketsToBuy == 0) {
            revert TicketEng__NotAllowed();
        }
        // Can't buy tickets of dead or nonexistent prophets
        bool targetProphetAlive;
        (, targetProphetAlive,,) = getProphetData(_prophetNum);
        if (targetProphetAlive == false || _prophetNum >= i_gameContract.s_numberOfProphets()) {
            revert TicketEng__ProphetIsDead();
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
            revert TicketEng__AddressIsEliminated();
        }

        // Check if player owns any tickets of another prophet
        if (senderTicketCount != 0 && senderAllegiance != _prophetNum) {
            revert TicketEng__NotAllowed();
        }

        uint256 totalPrice = getPrice(i_gameContract.acolytes(_prophetNum), _ticketsToBuy);

        i_gameContract.increaseTicketsToValhalla(msg.sender, _ticketsToBuy);
        i_gameContract.increaseAcolytes(_prophetNum, _ticketsToBuy);
        i_gameContract.increaseTotalTickets(_ticketsToBuy);
        i_gameContract.increaseTokenDepositedThisGame(totalPrice);
        i_gameContract.setPlayerAllegiance(msg.sender, _prophetNum);
        emit gainReligion(_prophetNum, _ticketsToBuy, totalPrice, msg.sender);

        i_gameContract.depositGameTokens(msg.sender, totalPrice);
    }

    /**
     * @notice This function allows a player to sell their tickets.
     * @dev This function can only be called if the game is in progress.
     * @dev This function can only be called by a prophet.
     * @param _ticketsToSell The number of tickets to sell.
     */
    function loseReligion(uint256 _ticketsToSell) public nonReentrant {
        uint256 gameStatus = uint256(i_gameContract.gameStatus());
        if (gameStatus != 1) {
            revert TicketEng__NotInProgress();
        }
        // Can't sell tickets of a dead prophet
        uint256 gameNumber = i_gameContract.s_gameNumber();
        uint256 currentAllegiance = i_gameContract.allegiance(gameNumber, msg.sender);
        bool targetProphetAlive;
        (, targetProphetAlive,,) = getProphetData(currentAllegiance);
        if (targetProphetAlive == false) {
            revert TicketEng__ProphetIsDead();
        }
        // Prophets cannot sell tickets
        if (i_gameContract.prophetList(gameNumber, msg.sender)) {
            revert TicketEng__NotAllowed();
        }
        // User cannot sell more tickets than they own
        uint256 startingUserTickets = i_gameContract.ticketsToValhalla(gameNumber, msg.sender);
        if (_ticketsToSell > startingUserTickets || _ticketsToSell == 0) {
            revert TicketEng__NotEnoughTicketsOwned();
        }
        // Get price of selling tickets
        uint256 totalPrice = getPrice(i_gameContract.acolytes(currentAllegiance) - _ticketsToSell, _ticketsToSell);
        emit religionLost(currentAllegiance, _ticketsToSell, totalPrice, msg.sender);
        // Reduce the total number of tickets sold in the game by number of tickets sold by msg.sender
        i_gameContract.decreaseTotalTickets(_ticketsToSell);
        i_gameContract.decreaseAcolytes(currentAllegiance, _ticketsToSell);
        // Remove tickets from msg.sender's balance
        i_gameContract.decreaseTicketsToValhalla(msg.sender, _ticketsToSell);
        // If msg.sender sold all tickets then set allegiance to 0
        if ((startingUserTickets - _ticketsToSell) == 0) {
            i_gameContract.setPlayerAllegiance(msg.sender, 0);
        }
        // Subtract the price of tickets sold from s_tokensDepositedThisGame for this game
        i_gameContract.decreaseTokensDepositedThisGame(totalPrice);
        //Take 5% fee
        uint256 protocolFee = i_gameContract.s_protocolFee();
        i_gameContract.applyProtocolFee((totalPrice * protocolFee) / 10000);
        totalPrice = (totalPrice * (10000 - protocolFee) / 10000);

        i_gameContract.returnGameTokens(msg.sender, totalPrice);
    }

    /**
     * @notice This function allows a player to claim their tickets.
     * @dev This function can only be called if the game being claimed from has ended.
     * @dev This function can be called by any address to claim for any address.
     * @param _gameNumber The number of the game to claim tickets from.
     * @param _player The address to claim tickets for.
     */
    function claimTickets(uint256 _gameNumber, address _player) public nonReentrant {
        uint256 currentGameNumber = i_gameContract.s_gameNumber();
        if (_gameNumber >= currentGameNumber) {
            revert TicketEng__NotAllowed();
        }
        // TurnManager sets currentProphetTurn to game winner, so use this to check if allegiance is to the winner
        if (i_gameContract.allegiance(_gameNumber, _player) != i_gameContract.currentProphetTurn(_gameNumber)) {
            revert TicketEng__AddressIsEliminated();
        }
        uint256 startingUserTickets = i_gameContract.ticketsToValhalla(_gameNumber, _player);
        if (startingUserTickets == 0) {
            revert TicketEng__NotEnoughTicketsOwned();
        }

        uint256 tokensToSend = startingUserTickets * i_gameContract.tokensPerTicket(_gameNumber);
        // Remove tickets from msg.sender's balance
        i_gameContract.burnWinningTicketsByGame(_gameNumber, _player, startingUserTickets);

        emit ticketsClaimed(_player, tokensToSend, _gameNumber);

        i_gameContract.returnGameTokens(_player, tokensToSend);
    }

    /**
     * @notice This function calculates the price of tickets based on the supply and amount of tickets.
     * @dev This is the bonding curve that determines the ticket price for each prophet.
     * @param supply The supply of tickets.
     * @param amount The amount of tickets to calculate the price for.
     * @return The total price for the tickets being exchanged.
     */
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
}
