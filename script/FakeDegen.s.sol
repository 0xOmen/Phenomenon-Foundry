// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {FakeDegenERC20} from "../src/FakeDegenERC20.sol";

contract FakeDegen is Script {
    function run() public returns (FakeDegenERC20) {
        vm.startBroadcast();
        FakeDegenERC20 fakeDegen = new FakeDegenERC20(vm.envAddress("RECIPIENT_ADDRESS"));
        vm.stopBroadcast();
        return (fakeDegen);
    }
}
