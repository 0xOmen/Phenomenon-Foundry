// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockFunctionsRouterSimple} from "../test/mocks/MockFunctionsRouterSimple.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address chainlinkFunctionsRouter;
        bytes32 chainlinkFunctionsDONID;
        uint64 subscriptionId;
        address wETH;
        uint256 deployerKey;
    }

    uint256 public DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 84532) {
            activeNetworkConfig = getSepoliaBaseConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaBaseConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            chainlinkFunctionsRouter: 0xf9B8fc078197181C841c296C876945aaa425B278,
            chainlinkFunctionsDONID: 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000,
            wETH: 0x4200000000000000000000000000000000000006,
            subscriptionId: 313,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.chainlinkFunctionsRouter != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        ERC20Mock wETHMock = new ERC20Mock();
        // deploy MockFunctionsRouterSimple
        MockFunctionsRouterSimple mockFunctionsRouterSimple = new MockFunctionsRouterSimple();
        vm.stopBroadcast();

        NetworkConfig memory anvilNetworkConfig = NetworkConfig({
            chainlinkFunctionsRouter: address(mockFunctionsRouterSimple),
            chainlinkFunctionsDONID: bytes32(0),
            subscriptionId: 1234,
            wETH: address(wETHMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
        return anvilNetworkConfig;
    }
}
