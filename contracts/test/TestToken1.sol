pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken1 is ERC20 {
    constructor(uint256 _totalSupply) ERC20("TestToken1", "TT1") {
        _mint(msg.sender, _totalSupply * (10**uint256(decimals())));
    }
}
