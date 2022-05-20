pragma solidity ^0.8.0;



import "../core/DaoRegistry.sol";
import "../helpers/DaoHelper.sol";

abstract contract AdapterGuard {
    /**
     * @dev 只允许 已注册的 适配器 才能执行
     */
    modifier onlyAdapter(DaoRegistry dao) {
        
        require(
            DaoHelper.isInCreationModeAndHasAccess(dao) || dao.isAdapter(msg.sender),
            "onlyAdapter"
        );
        _;
    }

    // 同一区块内不能调用两次
    modifier reentrancyGuard(DaoRegistry dao) {

        require(
            dao.lockedAt() != block.number, 
            "reentrancy guard"
        );

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
        require(
            DaoHelper.isInCreationModeAndHasAccess(dao) || dao.hasAdapterAccess(msg.sender, flag),
            "access Denied"
        );
        _;
    }
}
