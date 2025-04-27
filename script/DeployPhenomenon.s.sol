// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Phenomenon} from "../src/Phenomenon.sol";
import {GameplayEngine} from "../src/GameplayEngine.sol";
import {PhenomenonTicketEngine} from "../src/PhenomenonTicketEngine.sol";

contract DeployPhenomenon is Script {
    function run()
        public
        returns (address, bytes32, address, uint256, Phenomenon, PhenomenonTicketEngine, GameplayEngine)
    {
        HelperConfig helperConfig = new HelperConfig();

        (
            address chainlinkFunctionsRouter,
            bytes32 chainlinkFunctionsDONID,
            uint64 subscriptionId,
            address wETH,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        vm.startBroadcast(deployerKey);
        Phenomenon phenomenon = new Phenomenon(180, 0, 1000, 500, 4, wETH);
        GameplayEngine gameplayEngine = new GameplayEngine(
            address(phenomenon),
            "return Functions.encodeString('Hello World!');",
            subscriptionId,
            chainlinkFunctionsRouter,
            chainlinkFunctionsDONID
        );
        PhenomenonTicketEngine phenomenonTicketEngine = new PhenomenonTicketEngine(address(phenomenon), 1000);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        phenomenon.changeTicketEngine(address(phenomenonTicketEngine));
        vm.stopBroadcast();
        return (
            chainlinkFunctionsRouter,
            chainlinkFunctionsDONID,
            wETH,
            deployerKey,
            phenomenon,
            phenomenonTicketEngine,
            gameplayEngine
        );
    }
}
