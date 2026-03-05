// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {GameplayEngine} from "../src/GameplayEngine.sol";

/**
 * @notice Deploys only the GameplayEngine contract to Base Sepolia.
 * @dev Does NOT call phenomenon.changeGameplayEngine() - do that manually after deployment.
 * @dev Set PHENOMENON_ADDRESS in .env to the Phenomenon contract address (default: 0x47e7517c0641e00b06429eaedc4fdd331ba2df13)
 */
contract DeployGameplayEngine is Script {
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

    function run() public returns (GameplayEngine) {
        address phenomenonAddress = vm.envOr("PHENOMENON_ADDRESS", address(0x47e7517c0641E00b06429EAEdc4fDd331ba2DF13));

        HelperConfig helperConfig = new HelperConfig();
        (
            address chainlinkFunctionsRouter,
            bytes32 chainlinkFunctionsDONID,
            uint64 subscriptionId,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        require(block.chainid == 84532, "DeployGameplayEngine: run on Base Sepolia (chain 84532)");

        if (deployerKey == 0) {
            vm.startBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
        }

        GameplayEngine gameplayEngine = new GameplayEngine(
            phenomenonAddress,
            source,
            subscriptionId,
            chainlinkFunctionsRouter,
            chainlinkFunctionsDONID
        );

        vm.stopBroadcast();

        return gameplayEngine;
    }
}
