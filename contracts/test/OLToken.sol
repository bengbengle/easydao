// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OLToken is ERC20 {
    constructor(uint256 _totalSupply) ERC20("OpenLawToken", "OLT") {
        _mint(msg.sender, _totalSupply);
    }

    /**
     * 添加了 辅助功能 以使其与 TributeDAO 中的 治理令牌 兼容  
     * 任何治理代币 都必须实现 此功能 以跟踪历史余额
     * 在这种情况下，它只是一个忽略 快照号 的虚拟函数， 读取当前余额， 但理想情况下它有一个内部存储来跟踪,  每个代币持有者的历史余额 
     */
    function getPriorAmount(address account, uint256)
        public
        view
        returns (uint256)
    {
        return balanceOf(account);
    }
}
