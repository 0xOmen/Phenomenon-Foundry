// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";

contract MockFunctionsRouterSimple {
    bytes32[] private s_requestIds;

    function _sendRequest(bytes memory _data, uint64 _subscriptionId, uint32 _gasLimit, bytes32 _donId)
        external
        returns (bytes32)
    {
        // TODO: Implement the logic to send a request to the Functions Router
        bytes32 requestId = keccak256(abi.encode(block.timestamp, msg.sender, _data));

        s_requestIds.push(requestId);
        return requestId;
    }

    /*
    ("0") - Failed miracle
    ("1") - Successful miracle
    ("2") - Failed smite
    ("3") - Successful smite
    ("4") - Failed accusation
    ("5") - Successful accusation
    ("0111") - Game start with first prophet as high priest
    */
    function _fulfillRequest(string memory _outcome) external pure returns (bytes memory) {
        // TODO: Implement the logic to fulfill a request
        // check the length of _outcome
        bytes memory response;
        bytes memory text = bytes(_outcome);
        //console2.logBytes(text);
        if (text.length == 1) {
            response = text;
            //console.log("single outcome");
        } else {
            for (uint256 i = 0; i < text.length; i++) {
                response = bytes.concat(response, text[i]);
                //response = abi.encode(text[i]);
                //console2.logBytes1(text[i]);
                //console.log("multiple outcome");
            }
        }

        return response;
    }
}
