pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ProxTokenContract is ERC20 {
    event MintedProxToken(address owner, uint256 amount);

    constructor() ERC20("ProxToken", "PRX") {
        _mint(msg.sender, 0);
    }

    /**
     * Public function open to anyone that wants to mint new tokens in this test contract.
     */
    function mint(uint256 amount) external {
        address owner = msg.sender;
        _mint(owner, amount);
        emit MintedProxToken(owner, amount);
    }
}
