pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../helpers/DaoHelper.sol";

abstract contract AdapterGuard {
    /**
     * @dev Only registered adapters are allowed to execute the function call.
     * @dev 只允许注册的适配器执行函数调用
     */
    modifier onlyAdapter(DaoRegistry dao) {
        require(
            dao.isAdapter(msg.sender) ||
                DaoHelper.isInCreationModeAndHasAccess(dao),
            "onlyAdapter"
        );
        _;
    }
    
    // 同一区块内不能调用两次
    modifier reentrancyGuard(DaoRegistry dao) {
        require(dao.lockedAt() != block.number, "reentrancy guard");
        dao.lockSession();
        _;
        dao.unlockSession();
    }

    modifier executorFunc(DaoRegistry dao) {
        address executorAddr = dao.getExtensionAddress(keccak256("executor-ext"));
        
        require(address(this) == executorAddr, "only callable by the executor");
        _;
    }
    
    modifier hasAccess(DaoRegistry dao, DaoRegistry.AclFlag flag) {
        require(DaoHelper.isInCreationModeAndHasAccess(dao) || dao.hasAdapterAccess(msg.sender, flag), "access Denied");
        _;
    }
}
