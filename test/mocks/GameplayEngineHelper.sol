// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GameplayEngine} from "../../src/GameplayEngine.sol";

contract GameplayEngineHelper is GameplayEngine {
    constructor(address _gameContract, string memory _source, uint64 _subscriptionId, address _router, bytes32 _donId)
        GameplayEngine(_gameContract, _source, _subscriptionId, _router, _donId)
    {}

    function fulfillRequestHarness(bytes32 requestId, bytes memory response, bytes memory err) external {
        super.fulfillRequest(requestId, response, err);
    }
}
