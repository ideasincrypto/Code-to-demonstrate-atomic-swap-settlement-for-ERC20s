//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Generic Token Used for Testing
contract Gen20Token is ERC20 {
    constructor(
        uint256 initialSupply, 
        string memory name, 
        string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}