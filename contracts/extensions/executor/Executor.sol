pragma solidity ^0.8.0;



import "../../core/DaoRegistry.sol";
import "../IExtension.sol";

/**
 * @dev 代理合约使用 EVM 
 * 指令 `delegatecall` 执行对另一个合约的委托调用，调用是通过回退函数触发的 
 * 调用在由其地址通过 `implementation` 参数标识的目标合约中执行 
 * 委托调用的成功和返回数据返回给代理的调用者 
 * 只有带有 ACL Flag: EXECUTOR 的合约才允许使用代理委托调用功能 
 */
contract ExecutorExtension is IExtension {
    using Address for address payable;

    bool public initialized = false;
    DaoRegistry public dao;

    enum AclFlag {
        EXECUTE
    }

    constructor() {}

    modifier hasExtensionAccess(AclFlag flag) {
        require(
            (address(this) == msg.sender ||
                address(dao) == msg.sender ||
                DaoHelper.isInCreationModeAndHasAccess(dao) ||
                dao.hasAdapterAccessToExtension(
                    msg.sender,
                    address(this),
                    uint8(flag)
                )),
            "executorExt::accessDenied"
        );
        _;
    }

    /**
    * @notice 初始化与 DAO 关联的 Executor 扩展 
    * @dev 只能调用一次 
    * @param creator DAO 的创建者，他将是初始成员    
    */
    function initialize(DaoRegistry _dao, address creator) external override {
        require(!initialized, "executorExt::already initialized");
        require(_dao.isMember(creator), "executorExt::not member");
        dao = _dao;
        initialized = true;
    }

    /**
     * @dev 将调用委托给 发件人地址的 fallback function。 如果合约中没有其他函数与调用数据匹配，则将运行
     */
    // 只有启用了 EXECUTE ACL 标志的发送者才被允许发送 eth
    fallback() external payable {
        _fallback();
    }

    /**
     * @dev 将调用委托给`_implementation()`返回的地址的后备函数。 如果呼叫数据 为空，将运行。
     */
    // 只有启用了 EXECUTE ACL 标志的发送者才被允许发送 eth
    receive() external payable {
        _fallback();
    }
    
    /**
      * @dev 将当前调用委托给发件人地址
      */
    function _fallback() internal virtual {
        _delegate(msg.sender);
    }

    /**
    * @dev 将当前调用委托给 `implementation` 
    */
    function _delegate(address implementation)
        internal
        virtual
        hasExtensionAccess(AclFlag.EXECUTE)
    {
        require(
            DaoHelper.isNotZeroAddress(implementation),
            "executorExt: impl address can not be zero"
        );
        require(
            DaoHelper.isNotReservedAddress(implementation),
            "executorExt: impl address can not be reserved"
        );

        address daoAddr;
        bytes memory data = msg.data;
        assembly {
            daoAddr := mload(add(data, 36))
        }

        require(daoAddr == address(dao), "wrong dao!");

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // 复制 msg.data， 我们在这个内联汇编 
            // 块中完全控制内存，因为它不会返回到 Solidity 代码， 我们在内存位置 0 处覆盖 Solidity 便签本
            calldatacopy(0, 0, calldatasize())
            
            // 调用实现  out 和 outsize 为 0，因为我们还不知道大小
            let result := delegatecall(
                gas(),
                implementation,
                0,
                calldatasize(),
                0,
                0
            )

            // 复制返回的数据
            returndatacopy(0, 0, returndatasize())

            // delegatecall 出错时返回 0
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
