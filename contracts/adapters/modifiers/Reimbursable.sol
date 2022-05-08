pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/DaoRegistry.sol";
import "../../companion/interfaces/IReimbursement.sol";
import "./ReimbursableLib.sol";

abstract contract Reimbursable {
    struct ReimbursementData {
        // 在执行操作之前有多少气体
        uint256 gasStart;
        // 交易是否应报销
        bool shouldReimburse;
        // 花费限制期（以秒为单位）
        uint256 spendLimitPeriod;
        // 用于报销的适配器地址
        IReimbursement reimbursement;
    }

    /**
     * @dev 只允许注册过的适配器 执行函数调用
     */
    modifier reimbursable(DaoRegistry dao) {
        ReimbursementData memory data = ReimbursableLib.beforeExecution(dao);
        _;
        ReimbursableLib.afterExecution(dao, data);
    }
}
