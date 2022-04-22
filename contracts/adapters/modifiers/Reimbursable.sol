pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/DaoRegistry.sol";
import "../../companion/interfaces/IReimbursement.sol";
import "./ReimbursableLib.sol";

/**
MIT License

Copyright (c) 2021 Openlaw

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */
abstract contract Reimbursable {
    struct ReimbursementData {
        uint256 gasStart; // how much gas is left before executing anything, 在执行任何操作之前还剩下多少气体
        bool shouldReimburse; // should the transaction be reimbursed or not ?, 交易是否应报销
        uint256 spendLimitPeriod; // how long (in seconds) is the spend limit period, 花费限制期有多长（以秒为单位）
        IReimbursement reimbursement; // which adapter address is used for reimbursement, 报销使用哪个适配器地址
    }

    /**
     * @dev Only registered adapters are allowed to execute the function call.
     * @dev 只允许注册的适配器执行函数调用
     */
    modifier reimbursable(DaoRegistry dao) {
        ReimbursementData memory data = ReimbursableLib.beforeExecution(dao);
        _;
        ReimbursableLib.afterExecution(dao, data);
    }
}
