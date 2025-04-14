// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Phenomenon
 * @author 0x-Omen.eth
 *
 * Phenomenon is a game of survival, charisma, and wit. Prophets win by converting acolytes
 * and successfully navigating the game design. The last prophet alive, and any of their
 * acolytes, wins the game.
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
    error Game__NotAllowed();
    error Game__NotEnoughTicketsOwned();
    error Game__ProphetNotFree();
    error Game__OutOfTurn();
    error Game__OnlyOwner();
    error Game__OnlyController();
    error Game__MinimumTimeNotPassed();
    ///////////////////////////// Types ///////////////////////////////////

    enum GameState {
        OPEN,
        IN_PROGRESS,
        AWAITING_RESPONSE,
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
    uint256 public s_totalTickets;
    uint256 private encryptor;

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
    uint256[] public acolytes;

    /// @notice tracks how many high priests each prophet has
    /// @notice high priests cannot buy or sell tickets but can change allegiance
    /// @dev gets 'deleted' every game in reset()
    uint256[] public highPriestsByProphet;

    /// @notice tracks how many tickets there are in the game (acolytes + high priests)
    /// @dev gets set to 0 every game in reset()

    ////////////////////////// Events ////////////////////////////
    event gameStarted(uint256 indexed gameNumber);
    event miracleAttempted(bool indexed isSuccess, uint256 indexed currentProphetTurn);
    event smiteAttempted(uint256 indexed target, bool indexed isSuccess, uint256 indexed currentProphetTurn);
    event accusation(
        bool indexed isSuccess, bool targetIsAlive, uint256 indexed currentProphetTurn, uint256 indexed _target
    );
    event gameEnded(uint256 indexed gameNumber, uint256 indexed tokensPerTicket, uint256 indexed currentProphetTurn);
    event gameReset(uint256 indexed newGameNumber);
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

    function setMaxInterval(uint256 _newMaxInterval) public onlyOwner {
        s_maxInterval = _newMaxInterval;
    }

    function setMinInterval(uint256 _newMinInterval) public onlyOwner {
        s_minInterval = _newMinInterval;
    }

    function setRandomnessSeed(uint256 randomnessSeed) public onlyContract(s_gameplayEngine) {
        s_randomnessSeed = randomnessSeed;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////
    //////////// PROPHET FUNCTIONS /////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////
    function registerProphet(address _prophet) public onlyContract(s_gameplayEngine) {
        ProphetData memory newProphet;
        newProphet.playerAddress = _prophet;
        newProphet.isAlive = true;
        newProphet.isFree = true;
        prophets.push(newProphet);
        prophetList[s_gameNumber][_prophet] = true;
        s_prophetsRemaining++;
        uint256 prophetNum = prophets.length - 1;
        // assign allegiance to self
        allegiance[s_gameNumber][_prophet] = prophetNum;
        // give Prophet one of his own tickets
        ticketsToValhalla[s_gameNumber][prophets[prophetNum].playerAddress] = 1;
        // Increment total tickets by 1
        s_totalTickets++;
        // This initializes acolytes[]
        // Push the number of acolytes/tickets sold into the prophet slot of the array
        acolytes.push(1);
    }

    function getProphetData(uint256 _prophetNum) public view returns (address, bool, bool, uint256) {
        return (
            prophets[_prophetNum].playerAddress,
            prophets[_prophetNum].isAlive,
            prophets[_prophetNum].isFree,
            prophets[_prophetNum].args
        );
    }

    function updateProphetLife(uint256 _prophetNum, bool _isAlive) public onlyContract(s_gameplayEngine) {
        prophets[_prophetNum].isAlive = _isAlive;
    }

    function updateProphetFreedom(uint256 _prophetNum, bool _isFree) public onlyContract(s_gameplayEngine) {
        prophets[_prophetNum].isFree = _isFree;
    }

    function checkProphetList(address target) public view returns (bool) {
        return prophetList[s_gameNumber][target];
    }

    function setProphetTurn(uint256 _prophetNum) public onlyContract(s_gameplayEngine) {
        currentProphetTurn[s_gameNumber] = _prophetNum;
    }

    function getCurrentProphetTurn() public view returns (uint256) {
        return currentProphetTurn[s_gameNumber];
    }

    function changeGameStatus(uint256 _status) public onlyContract(s_gameplayEngine) {
        gameStatus = GameState(_status);
    }

    function updateProphetsRemaining(uint256 _add, uint256 _subtract) public onlyContract(s_gameplayEngine) {
        s_prophetsRemaining += _add;
        s_prophetsRemaining -= _subtract;
    }

    function updateProphetArgs(uint256 _prophetNum, uint256 _args) public onlyContract(s_gameplayEngine) {
        prophets[_prophetNum].args = _args;
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
            // Remove tickets held by Prophet's acolyte from totalTickets for TicketShare calc
            // Should this be plus or minus? I think it should be acolytes plus highPriests
            s_totalTickets -=
                (acolytes[currentProphetTurn[s_gameNumber]] + highPriestsByProphet[currentProphetTurn[s_gameNumber]]);
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
            // Remove target Prophet's acolyte tickets from totalTickets for TicketShare calc
            s_totalTickets -= (acolytes[_target] + highPriestsByProphet[_target]);
            // decrease number of remaining prophets
            s_prophetsRemaining--;
        } else {
            if (prophets[currentProphetTurn[s_gameNumber]].isFree == true) {
                prophets[currentProphetTurn[s_gameNumber]].isFree = false;
            } else {
                prophets[currentProphetTurn[s_gameNumber]].isAlive = false;
                // Remove Prophet's acolyte tickets from totalTickets for TicketShare calc
                s_totalTickets -= (
                    acolytes[currentProphetTurn[s_gameNumber]] + highPriestsByProphet[currentProphetTurn[s_gameNumber]]
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
                // Remove Prophet's acolyte tickets from totalTickets for TicketShare calc
                s_totalTickets -= (acolytes[_target] + highPriestsByProphet[_target]);
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

        delete acolytes; //array
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
                acolytes[currentProphetTurn[s_gameNumber]] + highPriestsByProphet[currentProphetTurn[s_gameNumber]];
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
        else return ((acolytes[_playerNum] + highPriestsByProphet[_playerNum]) * 100) / s_totalTickets;
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

    function increaseAcolytes(uint256 target, uint256 amount) public {
        if (msg.sender != s_ticketEngine || msg.sender != s_gameplayEngine) return;
        acolytes[target] += amount;
    }

    function decreaseAcolytes(uint256 target, uint256 amount) public {
        if (msg.sender != s_ticketEngine || msg.sender != s_gameplayEngine) return;
        acolytes[target] -= amount;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////
    ///////////// TOKEN FUNCTIONS //////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////

    function increaseTokenDepositedThisGame(uint256 amount) public onlyContract(s_ticketEngine) {
        s_tokensDepositedThisGame += amount;
    }

    function decreaseTokensDepositedThisGame(uint256 amount) public onlyContract(s_ticketEngine) {
        s_tokensDepositedThisGame -= amount;
    }

    function applyProtocolFee(uint256 amount) public onlyContract(s_ticketEngine) {
        s_ownerTokenBalance += amount;
    }

    // non-reentrant?
    function depositGameTokens(address from, uint256 amount) external onlyContract(s_ticketEngine) {
        IERC20(GAME_TOKEN).transferFrom(from, address(this), amount);
    }
    // non-reentrant?

    function returnGameTokens(address to, uint256 amount) external onlyContract(s_ticketEngine) {
        IERC20(GAME_TOKEN).transfer(to, amount);
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
}
