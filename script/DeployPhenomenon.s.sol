// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Phenomenon} from "../src/Phenomenon.sol";
import {GameplayEngine} from "../src/GameplayEngine.sol";
import {PhenomenonTicketEngine} from "../src/PhenomenonTicketEngine.sol";

contract DeployPhenomenon is Script {
    uint256 maxInterval = 180;
    uint256 minInterval = 0;
    uint256 entranceFee = 500000;
    uint256 protocolFee = 500;
    uint16 numProphets = 4;
    uint256 ticketMultiplier = 100000;

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
        vm.startBroadcast(deployerKey);
        Phenomenon phenomenon =
            new Phenomenon(maxInterval, minInterval, entranceFee, protocolFee, numProphets, gameToken);
        GameplayEngine gameplayEngine = new GameplayEngine(
            address(phenomenon),
            "return Functions.encodeString('Hello World!');",
            subscriptionId,
            chainlinkFunctionsRouter,
            chainlinkFunctionsDONID
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
