pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OLToken is ERC20 {
    constructor(uint256 _totalSupply) ERC20("OpenLawToken", "OLT") {
        _mint(msg.sender, _totalSupply);
    }

    /**
     * 添加了辅助功能以使其与 Tribute DAO 中的治理令牌兼容  
     * 任何治理代币都必须实现此功能以跟踪历史余额
     * 在这种情况下，它只是一个忽略块/快照编号的虚拟函数，并且读取当前余额，但理想情况下它会有一个内部存储来跟踪, 每个代币持有者的历史余额
     */
    function getPriorAmount(address account, uint256)
        public
        view
        returns (uint256)
    {
        return balanceOf(account);
    }
}
