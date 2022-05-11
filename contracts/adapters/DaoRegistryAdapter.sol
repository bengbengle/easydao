pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "../guards/MemberGuard.sol";
import "../guards/AdapterGuard.sol";
import "../adapters/interfaces/IVoting.sol";

contract DaoRegistryAdapterContract is MemberGuard, AdapterGuard {
    /**
     * @notice 允许成员/顾问更新他们的委托密钥
     * @param dao The DAO address.
     * @param delegateKey the new delegate key.
     */
    function updateDelegateKey(DaoRegistry dao, address delegateKey)
        external
        reentrancyGuard(dao)
    {
        address dk = dao.getCurrentDelegateKey(msg.sender);
        if (dk != msg.sender && dao.isMember(dk)) {
            dao.updateDelegateKey(msg.sender, delegateKey);
        } else {
            require(dao.isMember(msg.sender), "only member");
            dao.updateDelegateKey(
                DaoHelper.msgSender(dao, msg.sender),
                delegateKey
            );
        }
    }
}
