// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Phenomenon} from "../src/Phenomenon.sol";
import {GameplayEngine} from "../src/GameplayEngine.sol";
import {PhenomenonTicketEngine} from "../src/PhenomenonTicketEngine.sol";
import {DeployPhenomenon} from "../script/DeployPhenomenon.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract PhenomenonTest is Test {
    Phenomenon public phenomenon;
    PhenomenonTicketEngine public phenomenonTicketEngine;
    GameplayEngine public gameplayEngine;
    HelperConfig public helperConfig;

    address public chainlinkFunctionsRouter;
    bytes32 public chainlinkFunctionsDONID;
    address public weth;
    uint256 public deployerKey;
    address public owner;
    address public user1 = address(1);

    function setUp() public {
        DeployPhenomenon deployer = new DeployPhenomenon();
        (
            chainlinkFunctionsRouter,
            chainlinkFunctionsDONID,
            weth,
            deployerKey,
            phenomenon,
            phenomenonTicketEngine,
            gameplayEngine
        ) = deployer.run();
        // set owner to the owner of the phenomenon contract
        owner = phenomenon.getOwner();
        ERC20Mock(weth).mint(user1, 1000 ether);
    }

    function testOwnerCanChangeGameplayEngine() public {
        vm.startPrank(owner);
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
    }

    function testNonOwnerCannotChangeGameplayEngine() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(Phenomenon.Game__OnlyOwner.selector));
        phenomenon.changeGameplayEngine(address(gameplayEngine));
        vm.stopPrank();
    }

    function testOnlyGameplayEngineCanCallEntry() public {
        vm.startPrank(address(user1));
        vm.expectRevert(abi.encodeWithSelector(Phenomenon.Game__OnlyController.selector));
        phenomenon.registerProphet(address(user1));
        vm.stopPrank();
    }

    function testEnterGame() public {
        vm.startPrank(address(user1));
        ERC20Mock(weth).approve(address(phenomenon), 1000 ether);
        gameplayEngine.enterGame(new bytes32[](0));
        vm.stopPrank();
    }
}
