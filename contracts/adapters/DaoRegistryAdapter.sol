pragma solidity ^0.8.0;



import "../core/DaoRegistry.sol";
import "../guards/MemberGuard.sol";
import "../guards/AdapterGuard.sol";

contract DaoRegistryAdapterContract is MemberGuard, AdapterGuard {
    /**
     * @notice 允许成员/顾问更新他们的 委派账户
     * @param dao The DAO address.
     * @param delegateKey the new delegate key.
     */
    function updateDelegateKey(DaoRegistry dao, address delegateKey)
        external
        reentrancyGuard(dao)
    {
        address dk = dao.getCurrentDelegateKey(msg.sender);
        if (dao.isMember(dk) && dk != msg.sender) {
            dao.updateDelegateKey(
                msg.sender,
                delegateKey
            );
        } else {
            require(dao.isMember(msg.sender), "only member");
            dao.updateDelegateKey(
                DaoHelper.msgSender(dao, msg.sender),
                delegateKey
            );
        }
    }
}
