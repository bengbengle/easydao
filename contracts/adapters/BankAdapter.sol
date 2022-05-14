pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "../guards/AdapterGuard.sol";
import "../adapters/interfaces/IVoting.sol";
import "../helpers/DaoHelper.sol";
import "./modifiers/Reimbursable.sol";

contract BankAdapterContract is AdapterGuard, Reimbursable {
    /**
     * @notice 允许 DAO 的成员 / 顾问从 其内部银行账户 中提取资金  
     * @notice 只有未预留的账户才能提取资金  
     * @notice 如果用户账户中没有可用余额，则交易被撤销  
     * @param dao DAO 地址  
     * @param account 接收资金的账户  
     * @param token 接收资金的代币地址 
     */
    function withdraw(DaoRegistry dao, address payable account, address token) 
        external 
        reimbursable(dao) 
    {
        require(DaoHelper.isNotReservedAddress(account), "withdraw::reserved address");

        // 我们不需要检查token是否被银行支持， 因为如果不是，余额将永远为零 
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );

        uint256 balance = bank.balanceOf(account, token);
        require(balance > 0, "nothing to withdraw");

        bank.withdraw(dao, account, token, balance);
    }

    /**
     * @notice 允许任何人更新银行扩展中的 代币余额 
     * @notice 如果用户账户中没有可用余额，则交易被撤销  
     * @param dao DAO 地址  
     * @param token 要更新的令牌地址 
     */
    function updateToken(DaoRegistry dao, address token)
        external
        reentrancyGuard(dao)
    {
        // 我们 不需要检查 token 是否被银行支持， 因为如果不是，余额将永远为零 
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        
        bank.updateToken(dao, token);

        // bank.updateToken(dao, token);
    }

    /*
     * @notice 允许任何人将 eth 发送到银行分机
     * @param dao DAO 的地址
     */
    function sendEth(DaoRegistry dao) 
        external 
        payable 
        reimbursable(dao) 
    {
        require(msg.value > 0, "no eth sent!");

        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );

        bank.addToBalance{value: msg.value}(
            dao,
            DaoHelper.GUILD,
            DaoHelper.ETH_TOKEN,
            msg.value
        );
    }
}
