// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Phenomenon
 * @author 0x-Omen.eth
 *
 * Phenomenon is a game of survival, charisma, and wit. Prophets win by gaining accolites
 * and successfully navigating the game design. The last prophet alive, and any of their
 * accolites, wins the game.
 *
 * @dev This is the main Game contract that stores game state.
 */
contract Phenomenon {
    ///////////////////////////// Errors ///////////////////////////////////
    error Game__NotOpen();
    error Game__Full();
    error Game__AlreadyRegistered();
    error Game__ProphetNumberError();
    error Game__NotInProgress();
    error Game__ProphetIsDead();
    error Game__NotAllowed();
    error Game__NotEnoughTicketsOwned();
    error Game__AddressIsEliminated();
    error Game__ProphetNotFree();
    error Game__OutOfTurn();
    error Game__OnlyOwner();
    error Game__OnlyController();
    error Game__NoRandomNumber();
    error Game__MinimumTimeNotPassed();
    ///////////////////////////// Types ///////////////////////////////////

    enum GameState {
        OPEN,
        IN_PROGRESS,
        PAUSED,
        ENDED
    }

    struct ProphetData {
        address playerAddress;
        bool isAlive;
        bool isFree;
        uint256 args;
    }
    /////////////////////// State Variables ///////////////////////////////

    /// @notice Maximum interval a player has take a turn before others can trigger a miracle.
    /// @dev Set interval to 3 minutes = 180
    uint256 s_maxInterval;

    /// @notice Wait time before next player can take a turn. This is optional.
    uint256 s_minInterval;

    uint256 s_entranceFee;
    ////////// ticketMultipler will need to be deleted after refacto/////////
    uint256 ticketMultiplier;

    /// @notice The number of prophets/players needed to start the game
    uint16 public s_numberOfProphets;
    address private immutable GAME_TOKEN;

    /// @notice The current game number
    /// @dev This is incremented every time a game ends in reset()
    /// @dev This cannot be allowed to be decremented or it will break contract security
    uint256 public s_gameNumber;
    address private owner;
    address private s_gameplayEngine;
    address private s_ticketEngine;

    /// @notice This tracks total tokens deposited each game and is  reset every game
    /// @dev this variable is used to calculate how much each winning ticket is worth
    uint256 public s_tokensDepositedThisGame;
    uint256 private s_ownerTokenBalance;
    uint256 public s_lastRoundTimestamp;
    /// @notice This tracks how many prophets are alive in the current game
    uint256 public s_prophetsRemaining;
    uint256 private s_randomnessSeed;

    ProphetData[] public prophets;
    GameState public gameStatus;
    mapping(uint256 => uint256) public currentProphetTurn;

    /// @notice mapping of addresses that have signed up to play by game: prophetList[s_gameNumber][address]
    /// @dev returns 0 if not signed up and 1 if address has signed up
    mapping(uint256 => mapping(address => bool)) public prophetList;

    /// @notice store which prophet an address holds allegiance tickets to: allegiance[s_gameNumber][address]
    /// @dev returns 0 if no allegiance, returns prophet number otherwise
    mapping(uint256 => mapping(address => uint256)) public allegiance;

    /// @notice tracks how many tickets an address owns: ticketsToValhalla[s_gameNumber][address]
    mapping(uint256 => mapping(address => uint256)) public ticketsToValhalla;

    /// @notice tracks the value of a ticket for each individual game: tokensPerTicket[s_gameNumber]
    /// @dev Value gets set at the end of each game in turnManager()
    /// @dev This value is multiplied by a player's tickets to determine how many tokens they receive
    mapping(uint256 => uint256) public tokensPerTicket;

    /// @notice tracks how many tickets to heaven have been sold for each Prophet
    /// @dev gets 'deleted' every game in reset()
    uint256[] public accolites;

    /// @notice tracks how many high priests each prophet has
    /// @notice high priests cannot buy or sell tickets but can change allegiance
    /// @dev gets 'deleted' every game in reset()
    uint256[] public highPriestsByProphet;

    /// @notice tracks how many tickets there are in the game (accolites + high priests)
    /// @dev gets set to 0 every game in reset()
    uint256 public s_totalTickets;
    uint256 encryptor;

    ////////////////////////// Events ////////////////////////////
    event prophetEnteredGame(uint256 indexed prophetNumber, address indexed sender, uint256 indexed gameNumber);
    event gameStarted(uint256 indexed gameNumber);
    event miracleAttempted(bool indexed isSuccess, uint256 indexed currentProphetTurn);
    event smiteAttempted(uint256 indexed target, bool indexed isSuccess, uint256 indexed currentProphetTurn);
    event accusation(
        bool indexed isSuccess, bool targetIsAlive, uint256 indexed currentProphetTurn, uint256 indexed _target
    );
    event gameEnded(uint256 indexed gameNumber, uint256 indexed tokensPerTicket, uint256 indexed currentProphetTurn);
    event gameReset(uint256 indexed newGameNumber);
    event religionLost(
        uint256 indexed _target, uint256 indexed numTicketsSold, uint256 indexed totalPrice, address sender
    );
    event gainReligion(
        uint256 indexed _target, uint256 indexed numTicketsBought, uint256 indexed totalPrice, address sender
    );
    event ticketsClaimed(uint256 indexed ticketsClaimed, uint256 indexed tokensSent, uint256 indexed gameNumber);
    event currentTurn(uint256 indexed nextProphetTurn);

    ////////////////////////// Modifiers ////////////////////////////
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert Game__OnlyOwner();
        }
        _;
    }

    modifier onlyContract(address controller) {
        if (msg.sender != controller) {
            revert Game__OnlyController();
        }
        _;
    }

    ////////////////////////// Functions ////////////////////////////
    constructor(
        uint256 _maxInterval, //180 (3 minutes)
        uint256 _minInterval, //0 (instant)
        uint256 _entranceFee, //10000000000000000000000  (10,000)
        uint16 _numProphets,
        address _gameToken //0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed $DEGEN
    ) {
        owner = msg.sender;
        s_maxInterval = _maxInterval;
        s_minInterval = _minInterval;
        s_entranceFee = _entranceFee;
        s_numberOfProphets = _numProphets;
        encryptor = 8;
        s_gameNumber = 0;
        gameStatus = GameState.OPEN;
        s_lastRoundTimestamp = block.timestamp;

        GAME_TOKEN = _gameToken;
        s_tokensDepositedThisGame = 0;
    }

    function changeOwner(address newOwner) public onlyOwner {
        owner = newOwner;
    }

    function changeGameplayEngine(address newGameplayEngine) public onlyOwner {
        s_gameplayEngine = newGameplayEngine;
    }

    function changeTicketEngine(address newTicketEngine) public onlyOwner {
        s_ticketEngine = newTicketEngine;
    }

    function ownerChangeGameState(GameState _status) public onlyOwner {
        gameStatus = _status;
    }

    function changeEntryFee(uint256 newFee) public onlyOwner {
        s_entranceFee = newFee;
    }

    function enterGame() public {
        if (gameStatus != GameState.OPEN) {
            revert Game__NotOpen();
        }
        if (prophets.length >= s_numberOfProphets) {
            revert Game__Full();
        }
        if (prophetList[s_gameNumber][msg.sender]) {
            revert Game__AlreadyRegistered();
        }
        ProphetData memory newProphet;
        newProphet.playerAddress = msg.sender;
        newProphet.isAlive = true;
        newProphet.isFree = true;
        prophets.push(newProphet);
        s_tokensDepositedThisGame += s_entranceFee;
        prophetList[s_gameNumber][msg.sender] = true;
        s_prophetsRemaining++;

        emit prophetEnteredGame(s_prophetsRemaining - 1, msg.sender, s_gameNumber);

        if (s_prophetsRemaining == s_numberOfProphets) {
            startGame();
        }

        IERC20(GAME_TOKEN).transferFrom(msg.sender, address(this), s_entranceFee);
    }

    function startGame() public {
        if (gameStatus != GameState.OPEN) {
            revert Game__NotOpen();
        }
        if (prophets.length != s_numberOfProphets) {
            revert Game__ProphetNumberError();
        }

        ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        s_randomnessSeed = uint256(blockhash(block.number - 1));

        // semi-randomly select which prophet goes first
        currentProphetTurn[s_gameNumber] = block.timestamp % s_numberOfProphets;
        // Check if prophet is chosenOne, if not then randomly assign to priest or prophet
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
                // This loop initializes accolites[]
                // each loop pushes the number of accolites/tickets sold into the prophet slot of the array
                highPriestsByProphet.push(1);
            } else {
                highPriestsByProphet.push(0);
                s_prophetsRemaining--;
                prophets[_prophet].isAlive = false;
                prophets[_prophet].args = 99;
            }
            accolites.push(0);
        }
        turnManager();
        gameStatus = GameState.IN_PROGRESS;
        emit gameStarted(s_gameNumber);
    }

    function ruleCheck() internal view {
        // Minimal time interval must have passed from last turn
        if (block.timestamp < s_lastRoundTimestamp + s_minInterval) {
            revert Game__MinimumTimeNotPassed();
        }
        // Game must be in progress
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        // Sending address must be their turn
        if (msg.sender != prophets[currentProphetTurn[s_gameNumber]].playerAddress) {
            revert Game__OutOfTurn();
        }
    }

    function performMiracle() public {
        // If turn time interval has passed then anyone can call performMiracle on current Prophet's turn
        // What if this gets called between games?
        if (block.timestamp < s_lastRoundTimestamp + s_maxInterval) {
            ruleCheck();
        }

        if (
            currentProphetTurn[s_gameNumber]
                == (s_randomnessSeed / (42069420690990990091337 * encryptor)) % s_numberOfProphets
                || ((block.timestamp) % 100) + (getTicketShare(currentProphetTurn[s_gameNumber]) / 10) >= 25
        ) {
            if (prophets[currentProphetTurn[s_gameNumber]].isFree == false) {
                prophets[currentProphetTurn[s_gameNumber]].isFree = true;
            }
        } else {
            // kill prophet
            prophets[currentProphetTurn[s_gameNumber]].isAlive = false;
            // Remove tickets held by Prophet's accolite from totalTickets for TicketShare calc
            // Should this be plus or minus? I think it should be accolites plus highPriests
            s_totalTickets -=
                (accolites[currentProphetTurn[s_gameNumber]] + highPriestsByProphet[currentProphetTurn[s_gameNumber]]);
            // decrease number of remaining prophets
            s_prophetsRemaining--;
        }
        emit miracleAttempted(prophets[currentProphetTurn[s_gameNumber]].isAlive, currentProphetTurn[s_gameNumber]);
        turnManager();
    }

    // game needs to be playing, prophet must be alive
    function attemptSmite(uint256 _target) public {
        ruleCheck();
        // Prophet to smite must be alive and exist
        if (_target >= s_numberOfProphets || prophets[_target].isAlive == false) {
            revert Game__NotAllowed();
        }

        prophets[currentProphetTurn[s_gameNumber]].args = _target;
        if (
            currentProphetTurn[s_gameNumber]
                == (s_randomnessSeed / (42069420690990990091337 * encryptor)) % s_numberOfProphets
                || 1 + (uint256(block.timestamp % 100) + (getTicketShare(currentProphetTurn[s_gameNumber]) / 2)) >= 90
        ) {
            // kill target prophet
            prophets[_target].isAlive = false;
            // Remove target Prophet's accolite tickets from totalTickets for TicketShare calc
            s_totalTickets -= (accolites[_target] + highPriestsByProphet[_target]);
            // decrease number of remaining prophets
            s_prophetsRemaining--;
        } else {
            if (prophets[currentProphetTurn[s_gameNumber]].isFree == true) {
                prophets[currentProphetTurn[s_gameNumber]].isFree = false;
            } else {
                prophets[currentProphetTurn[s_gameNumber]].isAlive = false;
                // Remove Prophet's accolite tickets from totalTickets for TicketShare calc
                s_totalTickets -= (
                    accolites[currentProphetTurn[s_gameNumber]] + highPriestsByProphet[currentProphetTurn[s_gameNumber]]
                );
                // decrease number of remaining prophets
                s_prophetsRemaining--;
            }
        }
        emit smiteAttempted(_target, !prophets[_target].isAlive, currentProphetTurn[s_gameNumber]);
        turnManager();
    }

    function accuseOfBlasphemy(uint256 _target) public {
        ruleCheck();
        // Prophet to accuse must be alive and exist
        if (_target >= s_numberOfProphets || prophets[_target].isAlive == false) {
            revert Game__NotAllowed();
        }
        // Message Sender must be living & free prophet on their turn
        if (prophets[currentProphetTurn[s_gameNumber]].isFree == false) {
            revert Game__ProphetNotFree();
        }
        prophets[currentProphetTurn[s_gameNumber]].args = _target;

        if (
            1
                + (
                    uint256((block.timestamp * currentProphetTurn[s_gameNumber]) % 100)
                        + getTicketShare(currentProphetTurn[s_gameNumber])
                ) > 90
        ) {
            if (prophets[_target].isFree == true) {
                prophets[_target].isFree = false;
                emit accusation(true, true, currentProphetTurn[s_gameNumber], _target);
            } else {
                // kill prophet
                prophets[_target].isAlive = false;
                // Remove Prophet's accolite tickets from totalTickets for TicketShare calc
                s_totalTickets -= (accolites[_target] + highPriestsByProphet[_target]);
                // decrease number of remaining prophets
                s_prophetsRemaining--;
                emit accusation(true, false, currentProphetTurn[s_gameNumber], _target);
            }
        } else {
            // set target free
            prophets[_target].isFree = true;
            // put failed accuser in jail
            prophets[currentProphetTurn[s_gameNumber]].isFree = false;
            emit accusation(false, true, currentProphetTurn[s_gameNumber], _target);
        }
        turnManager();
    }

    // Allow s_numberOfProphets to be changed in Hackathon but maybe don't let this happen in Production?
    // There may be a griefing vector I haven't thought of
    function reset(uint16 _numberOfPlayers) public {
        if (msg.sender != owner) {
            if (gameStatus != GameState.ENDED) {
                revert Game__NotInProgress();
            }
            if (block.timestamp < s_lastRoundTimestamp + 30) {
                revert Game__NotAllowed();
            }
            if (_numberOfPlayers < 4 || _numberOfPlayers > 9) {
                revert Game__ProphetNumberError();
            }
        }

        s_gameNumber++;
        s_tokensDepositedThisGame = 0;
        delete prophets; //array of structs
        gameStatus = GameState.OPEN;
        s_prophetsRemaining = 0;
        s_numberOfProphets = _numberOfPlayers;

        delete accolites; //array
        delete highPriestsByProphet; //array
        s_totalTickets = 0;
        emit gameReset(s_gameNumber);
    }

    function turnManager() internal {
        bool stillFinding = true;
        if (s_prophetsRemaining == 1) {
            gameStatus = GameState.ENDED;
            if (prophets[currentProphetTurn[s_gameNumber]].isAlive) {
                stillFinding = false;
            }

            uint256 winningTokenCount =
                accolites[currentProphetTurn[s_gameNumber]] + highPriestsByProphet[currentProphetTurn[s_gameNumber]];
            if (winningTokenCount != 0) {
                s_ownerTokenBalance += (s_tokensDepositedThisGame * 5) / 100;
                s_tokensDepositedThisGame = (s_tokensDepositedThisGame * 95) / 100;
                tokensPerTicket[s_gameNumber] = s_tokensDepositedThisGame / winningTokenCount;
            } else {
                tokensPerTicket[s_gameNumber] = 0;
                s_ownerTokenBalance += s_tokensDepositedThisGame;
            }
        }

        uint256 nextProphetTurn = currentProphetTurn[s_gameNumber] + 1;
        while (stillFinding) {
            if (nextProphetTurn >= s_numberOfProphets) {
                nextProphetTurn = 0;
            }
            if (prophets[nextProphetTurn].isAlive) {
                currentProphetTurn[s_gameNumber] = nextProphetTurn;
                s_lastRoundTimestamp = block.timestamp;
                stillFinding = false;
            }
            nextProphetTurn++;
        }
        emit currentTurn(currentProphetTurn[s_gameNumber]);
        if (s_prophetsRemaining == 1) {
            emit gameEnded(s_gameNumber, tokensPerTicket[s_gameNumber], currentProphetTurn[s_gameNumber]);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////
    //////////// TICKET FUNCTIONS //////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////
    function getTicketShare(uint256 _playerNum) public view returns (uint256) {
        if (s_totalTickets == 0) return 0;
        else return ((accolites[_playerNum] + highPriestsByProphet[_playerNum]) * 100) / s_totalTickets;
    }

    function increaseHighPriest(uint256 target) public onlyContract(s_ticketEngine) {
        highPriestsByProphet[target]++;
    }

    function decreaseHighPriest(uint256 target) public onlyContract(s_ticketEngine) {
        highPriestsByProphet[target]--;
    }

    function increaseTicketsToValhalla(address target, uint256 amount) public onlyContract(s_ticketEngine) {
        ticketsToValhalla[s_gameNumber][target] += amount;
    }

    function decreaseTicketsToValhalla(address target, uint256 amount) public onlyContract(s_ticketEngine) {
        ticketsToValhalla[s_gameNumber][target] -= amount;
    }

    function increaseTotalTickets(uint256 amount) public onlyContract(s_ticketEngine) {
        s_totalTickets += amount;
    }

    function decreaseTotalTickets(uint256 amount) public onlyContract(s_ticketEngine) {
        s_totalTickets -= amount;
    }

    function setPlayerAllegiance(address player, uint256 target) public onlyContract(s_ticketEngine) {
        allegiance[s_gameNumber][player] = target;
    }

    function getReligion(uint256 _prophetNum, uint256 _ticketsToBuy) public {
        // Make sure game state allows for tickets to be bought
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        // Prophets cannot buy tickets
        // the ability to send 'buy' 0 tickets allows changing of allegiance
        if (prophetList[s_gameNumber][msg.sender] || _ticketsToBuy == 0) {
            revert Game__NotAllowed();
        }
        // Can't buy tickets of dead or nonexistent prophets
        if (prophets[_prophetNum].isAlive == false || _prophetNum >= s_numberOfProphets) {
            revert Game__ProphetIsDead();
        }
        /*
        // Cannot buy/sell  tickets if address eliminated (allegiant to prophet when killed)
        // Addresses that own no tickets will default allegiance to 0 but 0 is a player number
        //  This causes issues with game logic so if allegiance is to 0
        //  we must also check if sending address owns tickets
        // If the address owns tickets then they truly have allegiance to player 0
        if (
            prophets[allegiance[s_gameNumber][msg.sender]].isAlive == false &&
            ticketsToValhalla[s_gameNumber][msg.sender] != 0
        ) {
            revert Game__AddressIsEliminated();
        }

        // Check if player owns any tickets of another prophet
        if (
            ticketsToValhalla[s_gameNumber][msg.sender] != 0 &&
            allegiance[s_gameNumber][msg.sender] != _prophetNum
        ) {
            revert Game__NotAllowed();
        } */

        uint256 totalPrice = getPrice(accolites[_prophetNum], _ticketsToBuy);

        ticketsToValhalla[s_gameNumber][msg.sender] += _ticketsToBuy;
        accolites[_prophetNum] += _ticketsToBuy;
        s_totalTickets += _ticketsToBuy;
        s_tokensDepositedThisGame += totalPrice;
        allegiance[s_gameNumber][msg.sender] = _prophetNum;
        emit gainReligion(_prophetNum, _ticketsToBuy, totalPrice, msg.sender);

        IERC20(GAME_TOKEN).transferFrom(msg.sender, address(this), totalPrice);
    }

    /*
    function loseReligion(uint256 _ticketsToSell) public {
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        // Can't sell tickets of a dead prophet
        if (prophets[allegiance[s_gameNumber][msg.sender]].isAlive == false) {
            revert Game__ProphetIsDead();
        }
        // Prophets cannot sell tickets
        if (prophetList[s_gameNumber][msg.sender]) {
            revert Game__NotAllowed();
        }
        if (
            _ticketsToSell <= ticketsToValhalla[s_gameNumber][msg.sender] &&
            _ticketsToSell != 0
        ) {
            // Get price of selling tickets
            uint256 totalPrice = getPrice(
                accolites[allegiance[s_gameNumber][msg.sender]] -
                    _ticketsToSell,
                _ticketsToSell
            );
            emit religionLost(
                allegiance[s_gameNumber][msg.sender],
                _ticketsToSell,
                totalPrice,
                msg.sender
            );
            // Reduce the total number of tickets sold in the game by number of tickets sold by msg.sender
            s_totalTickets -= _ticketsToSell;
            accolites[allegiance[s_gameNumber][msg.sender]] -= _ticketsToSell;
            // Remove tickets from msg.sender's balance
            ticketsToValhalla[s_gameNumber][msg.sender] -= _ticketsToSell;
            // If msg.sender sold all tickets then set allegiance to 0
            if (ticketsToValhalla[s_gameNumber][msg.sender] == 0)
                allegiance[s_gameNumber][msg.sender] = 0;
            // Subtract the price of tickets sold from the s_tokensDepositedThisGame for this game
            s_tokensDepositedThisGame -= totalPrice;
            //Take 5% fee
            s_ownerTokenBalance += (totalPrice * 5) / 100;
            totalPrice = (totalPrice * 95) / 100;

            IERC20(GAME_TOKEN).transfer(msg.sender, totalPrice);
        } else revert Game__NotEnoughTicketsOwned();
    }*/

    function claimTickets(uint256 _gameNumber) public {
        if (_gameNumber >= s_gameNumber) {
            revert Game__NotAllowed();
        }
        // TurnManager sets currentProphetTurn to game winner, so use this to check if allegiance is to the winner
        if (allegiance[_gameNumber][msg.sender] != currentProphetTurn[_gameNumber]) {
            revert Game__AddressIsEliminated();
        }
        if (ticketsToValhalla[_gameNumber][msg.sender] == 0) {
            revert Game__NotEnoughTicketsOwned();
        }

        uint256 tokensToSend = ticketsToValhalla[_gameNumber][msg.sender] * tokensPerTicket[_gameNumber];
        ticketsToValhalla[_gameNumber][msg.sender] = 0;

        emit ticketsClaimed(ticketsToValhalla[_gameNumber][msg.sender], tokensToSend, _gameNumber);

        IERC20(GAME_TOKEN).transfer(msg.sender, tokensToSend);
    }

    function getOwnerTokenBalance() public view returns (uint256) {
        return s_ownerTokenBalance;
    }

    function transferOwnerTokens(uint256 _amount, address _destination) public onlyOwner {
        if (_amount > s_ownerTokenBalance) {
            revert Game__NotEnoughTicketsOwned();
        }
        IERC20(GAME_TOKEN).transfer(_destination, _amount);
    }
    // This can be abused and should either be removed or revokable

    function ownerTokenTransfer(uint256 _amount, address _token, address _destination) public onlyOwner {
        IERC20(_token).transfer(_destination, _amount);
    }

    function setMaxInterval(uint256 _newMaxInterval) public onlyOwner {
        s_maxInterval = _newMaxInterval;
    }

    function setMinInterval(uint256 _newMinInterval) public onlyOwner {
        s_minInterval = _newMinInterval;
    }

    function getProphetData(uint256 _prophetNum) public view returns (address, bool, bool, uint256) {
        return (
            prophets[_prophetNum].playerAddress,
            prophets[_prophetNum].isAlive,
            prophets[_prophetNum].isFree,
            prophets[_prophetNum].args
        );
    }
}
