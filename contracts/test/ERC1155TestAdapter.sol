pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT
import "../core/DaoRegistry.sol";
import "../extensions/erc1155/ERC1155TokenExtension.sol";
import "../guards/AdapterGuard.sol";
import "../adapters/interfaces/IVoting.sol";
import "../helpers/DaoHelper.sol";

contract ERC1155TestAdapterContract is AdapterGuard {
    /**
     * @notice Internally transfers the NFT from one owner to a new owner as long as both are active members.
     * @notice Reverts if the addresses of the owners are not members.
     * @notice Reverts if the fromOwner does not hold the NFT.
     * @param dao The DAO address.
     * @param nftAddr The NFT smart contract address.
     * @param nftTokenId The NFT token id.
     * @param amount of the nftTokenId.
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
