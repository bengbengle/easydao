// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "../core/DaoRegistry.sol";
import "../extensions/erc1155/ERC1155TokenExtension.sol";
import "../guards/AdapterGuard.sol";
import "../helpers/DaoHelper.sol";

contract ERC1155TestAdapterContract is AdapterGuard {
    /**
    * @notice 在内部将 NFT 从一个所有者转移到一个新所有者，只要两者都是活跃成员
    * @notice 如果所有者的地址不是成员，则还原 
    * @notice 如果 fromOwner 不持有 NFT，则恢复
    * @param dao DAO 地址
    * @param nftAddr NFT 智能合约地址 
    * @param nftTokenId NFT 令牌 ID 
    * @param amount 数量
     */
    function internalTransfer(
        DaoRegistry dao,
        address nftAddr,
        uint256 nftTokenId,
        uint256 amount
    ) external reentrancyGuard(dao) {
        ERC1155TokenExtension erc1155 = ERC1155TokenExtension(
            dao.getExtensionAddress(DaoHelper.ERC1155_EXT)
        );
        erc1155.internalTransfer(
            dao,
            DaoHelper.GUILD,
            DaoHelper.msgSender(dao, msg.sender),
            nftAddr,
            nftTokenId,
            amount
        );
    }
}
