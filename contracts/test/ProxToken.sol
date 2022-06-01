// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ProxTokenContract is ERC20 {

    event MintedProxToken(address owner, uint256 amount);

    constructor() ERC20("ProxToken", "PRX") {
        _mint(msg.sender, 0);
    }

    /**
     * 公共功能 向 任何想要在 此 测试合约 中 铸造 新代币的人开放
     */
    function mint(uint256 amount) external {
        address owner = msg.sender;
        _mint(owner, amount);
        
        emit MintedProxToken(owner, amount);
    }
}
