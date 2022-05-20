pragma solidity ^0.8.0;


import "../../../core/DaoRegistry.sol";
import "../../../helpers/DaoHelper.sol";
import "../../bank/Bank.sol";
import "./IERC20TransferStrategy.sol";

/**
 * ERC20Extension 是为 DAO 成员持有的 内部代币
 */
contract ERC20TransferStrategySimple is IERC20TransferStrategy {

    bytes32 public constant ERC20_EXT_TRANSFER_TYPE = keccak256("erc20.transfer.type");

    // @notice 可克隆合约必须有一个空的构造函数
    // constructor() {}

    function hasBankAccess(DaoRegistry dao, address caller)
        public
        view
        returns (bool)
    {
        return
            dao.hasAdapterAccessToExtension(
                caller,
                dao.getExtensionAddress(DaoHelper.BANK),
                uint8(BankExtension.AclFlag.INTERNAL_TRANSFER)
            );
    }

    function evaluateTransfer(
        DaoRegistry dao,
        address,
        address,
        address to,
        uint256 amount,
        address caller
    ) external view override returns (ApprovalType, uint256) {
        // 如果转移是内部转移， 则使其无限制
        if (hasBankAccess(dao, caller)) {
            return (ApprovalType.SPECIAL, amount);
        }

        uint256 transferType = dao.getConfiguration(ERC20_EXT_TRANSFER_TYPE);
        // member only
        if (transferType == 0 && dao.isMember(to)) {
            // members only transfer
            return (ApprovalType.STANDARD, amount);
            // open transfer
        } else if (transferType == 1) {
            return (ApprovalType.STANDARD, amount);
        }
        // transfer not allowed，
        return (ApprovalType.NONE, 0);
    }
}
