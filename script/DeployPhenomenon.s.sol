// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Phenomenon} from "../src/Phenomenon.sol";
import {GameplayEngine} from "../src/GameplayEngine.sol";
import {PhenomenonTicketEngine} from "../src/PhenomenonTicketEngine.sol";

contract DeployPhenomenon is Script {
    uint256 maxInterval = 180;
    uint256 minInterval = 25;
    uint256 entranceFee = 500000; // $0.50 for USDC
    uint256 protocolFee = 500;
    uint16 numProphets = 4;
    uint256 ticketMultiplier = 100000;
    // forgefmt: disable-start
    string source = 'let response = "";'
        'let decryptor = 7983442720963060024057948886542171092952310290025484363884501439;'
        'if (secrets.decryptor) {'
        '  decryptor = secrets.decryptor;'
        '}'
        'const _RandomnessSeed = args[0];'
        'const _numProphets = args[1];'
        'const _action = args[2];'
        'const _currentProphetTurn = args[3];'
        'const _ticketShare = args[4];'
        'const chosenOne = Math.floor((_RandomnessSeed / decryptor) % _numProphets);'
        'console.log(`chosenOne = ${chosenOne}`);'
        'if (_action == 0) {'
        '  const miracleFailureOdds = 25;'
        '  let result = "1";'
        '  if (_currentProphetTurn != chosenOne) {'
        '    if (1 + ((Math.random() * 100) % 100) + _ticketShare / 10 < miracleFailureOdds)'
        '      result = "0";'
        '  }'
        '  response = response.concat(result);'
        '}'
        'else if (_action == 1) {'
        '  const smiteFailureOdds = 90;'
        '  let result = "3";'
        '  if (_currentProphetTurn != chosenOne) {'
        '    if (1 + ((Math.random() * 100) % 100) + _ticketShare / 2 < smiteFailureOdds)'
        '      result = "2";'
        '  }'
        '  response = response.concat(result);'
        '}'
        'else if (_action == 2) {'
        '  const accuseFailureOdds = 90;'
        '  let result = "5";'
        '  if (1 + ((Math.random() * 100) % 100) + _ticketShare < accuseFailureOdds) {'
        '    result = "4";'
        '  }'
        '  response = response.concat(result);'
        '}'
        'else if (_action == 3) {'
        '  for (let _prophet = 0; _prophet < _numProphets; _prophet++) {'
        '    const miracleFailureOdds = 25;'
        '    let result = "1";'
        '    if (_prophet != chosenOne) {'
        '      if (1 + ((Math.random() * 100) % 100) < miracleFailureOdds) result = "0";'
        '    }'
        '    response = response.concat(result);'
        '  }'
        '}'
        'console.log(`response = ${response}`);'
        'return Functions.encodeString(response);';
    // forgefmt:disable-end

    function run()
        public
        returns (address, bytes32, address, uint256, Phenomenon, PhenomenonTicketEngine, GameplayEngine)
    {
        HelperConfig helperConfig = new HelperConfig();

        (
            address chainlinkFunctionsRouter,
            bytes32 chainlinkFunctionsDONID,
            uint64 subscriptionId,
            address gameToken,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        if (deployerKey == 0) {
            vm.startBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
        }

        Phenomenon phenomenon =
            new Phenomenon(maxInterval, minInterval, entranceFee, protocolFee, numProphets, gameToken);
        GameplayEngine gameplayEngine = new GameplayEngine(
            address(phenomenon), source, subscriptionId, chainlinkFunctionsRouter, chainlinkFunctionsDONID
        );
        PhenomenonTicketEngine phenomenonTicketEngine =
            new PhenomenonTicketEngine(address(phenomenon), ticketMultiplier);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        phenomenon.changeTicketEngine(address(phenomenonTicketEngine));
        vm.stopBroadcast();
        return (
            chainlinkFunctionsRouter,
            chainlinkFunctionsDONID,
            gameToken,
            deployerKey,
            phenomenon,
            phenomenonTicketEngine,
            gameplayEngine
        );
    }
}
