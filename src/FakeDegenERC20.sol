// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FakeDegenERC20
 * @author 0x-Omen.eth
 * @notice This is a fake $DEGEN ERC20 token for testing purposes only.
 * @dev This token is not for production use. Only launch on Base Sepolia.
 */
contract FakeDegenERC20 is ERC20, ERC20Permit {
    constructor(address recipient) ERC20("Fake Degen", "fDEGEN") ERC20Permit("Fake Degen") {
        _mint(recipient, 1000000000 * 10 ** decimals());
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    function mint() public {
        _mint(msg.sender, 100000 * 10 ** decimals());
    }

    function mintAndSend(address to) public {
        _mint(to, 100000 * 10 ** decimals());
    }
}
