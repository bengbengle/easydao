// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "../../../core/DaoRegistry.sol";
import "../../../helpers/DaoHelper.sol";
import "../../bank/Bank.sol";
import "./IERC721TransferStrategy.sol";

/**
 * ERC721Extension 是为 DAO 成员持有的 内部代币
 */
contract ERC721TransferStrategySimple is IERC721TransferStrategy {

    bytes32 public constant ERC721_EXT_TRANSFER_TYPE = keccak256("erc721.transfer.type");

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
        uint256 tokenId,
        address caller
    ) external view override returns (ApprovalType, uint256) {
        // 如果转移是内部转移， 则使其无限制
        if (hasBankAccess(dao, caller)) {
            return (ApprovalType.SPECIAL, tokenId);
        }

        uint256 transferType = dao.getConfiguration(ERC721_EXT_TRANSFER_TYPE);
        // member only
        if (transferType == 0 && dao.isMember(to)) {
            // members only transfer
            return (ApprovalType.STANDARD, tokenId);
            // open transfer
        } else if (transferType == 1) {
            return (ApprovalType.STANDARD, tokenId);
        }
        // transfer not allowed，
        return (ApprovalType.NONE, 0);
    }
}
