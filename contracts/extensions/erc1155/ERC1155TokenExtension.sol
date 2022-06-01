// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../core/DaoRegistry.sol";
import "../../guards/MemberGuard.sol";
import "../../helpers/DaoHelper.sol";
import "../IExtension.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ERC1155TokenExtension is IExtension, IERC1155Receiver {
    using Address for address payable;
    //LIBRARIES
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    bool public initialized = false; //internally tracks deployment under eip-1167 proxy pattern
    DaoRegistry public dao;

    enum AclFlag {
        WITHDRAW_NFT,
        COLLECT_NFT,
        INTERNAL_TRANSFER
    }

    //EVENTS
    event TransferredNFT(
        address oldOwner,
        address newOwner,
        address nftAddr,
        uint256 nftTokenId,
        uint256 amount
    );
    event WithdrawnNFT(
        address nftAddr,
        uint256 nftTokenId,
        uint256 amount,
        address toAddress
    );

    //MAPPINGS

    // All the Token IDs that belong to an NFT address stored in the GUILD.
    mapping(address => EnumerableSet.UintSet) private _nfts;

    // The internal mapping to track the owners, nfts, tokenIds, and amounts records of the owners that sent ther NFT to the extension
    // owner => (tokenAddress => (tokenId => tokenAmount)).
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        private _nftTracker;

    // The (NFT Addr + Token Id) key reverse mapping to track all the tokens collected and actual owners.
    mapping(bytes32 => EnumerableSet.AddressSet) private _ownership;

    // All the NFT addresses stored in the Extension collection
    EnumerableSet.AddressSet private _nftAddresses;

    //MODIFIERS
    modifier hasExtensionAccess(DaoRegistry _dao, AclFlag flag) {
        require(
            _dao == dao &&
                (DaoHelper.isInCreationModeAndHasAccess(dao) ||
                    dao.hasAdapterAccessToExtension(
                        msg.sender,
                        address(this),
                        uint8(flag)
                    )),
            "erc1155Ext::accessDenied"
        );
        _;
    }

    /// @notice Clonable contract must have an empty constructor
    constructor() {}

    /**
     * @notice Initializes the extension with the DAO address that it belongs to.
     * @param _dao The address of the DAO that owns the extension.
     * @param creator The owner of the DAO and Extension that is also a member of the DAO.
     */
    function initialize(DaoRegistry _dao, address creator) external override {
        require(!initialized, "erc1155Ext::already initialized");
        require(_dao.isMember(creator), "erc1155Ext::not a member");

        initialized = true;
        dao = _dao;
    }

    /**
    * @notice 将 NFT 代币从扩展地址转移给新的所有者。 
    * @notice 它还更新内部状态以跟踪扩展收集的所有 NFT。 
    * @notice 调用者必须具有 ACL 标志： WITHDRAW_NFT 
    * @notice 此函数需要从将管理银行余额的新适配器 (RagequitNFT) 调用，并将 NFT 返回给所有者。 
    * @dev 如果 NFT 不在 ERC1155 标准中，则恢复。 
    * @param newOwner 将接收 NFT 的新所有者的地址。 
    * @param nftAddr 必须符合 ERC1155 标准的 NFT 地址。 
    * @param nftTokenId NFT 令牌 ID。 
    * @param amount 要提取的 NFT 代币 ID 数量。     
    */
    function withdrawNFT(
        DaoRegistry _dao,
        address from,
        address newOwner,
        address nftAddr,
        uint256 nftTokenId,
        uint256 amount
    ) external hasExtensionAccess(_dao, AclFlag.WITHDRAW_NFT) {
        IERC1155 erc1155 = IERC1155(nftAddr);
        uint256 balance = erc1155.balanceOf(address(this), nftTokenId);
        require(
            balance > 0 && amount > 0,
            "erc1155Ext::not enough balance or amount"
        );

        uint256 currentAmount = _getTokenAmount(from, nftAddr, nftTokenId);
        require(currentAmount >= amount, "erc1155Ext::insufficient funds");
        uint256 remainingAmount = currentAmount - amount;

        // 更新 tokenID 数量以保持记录一致
        _updateTokenAmount(from, nftAddr, nftTokenId, remainingAmount);

        uint256 ownerTokenIdBalance = erc1155.balanceOf(
            address(this),
            nftTokenId
        ) - amount;

        // 如果 Extension 中的 tokenId 数量为 0，则更新映射 
        // 这意味着 GUILD/Extension 不再持有该 token id。    
        if (ownerTokenIdBalance == 0) {
            delete _nftTracker[newOwner][nftAddr][nftTokenId];

            _ownership[getNFTId(nftAddr, nftTokenId)].remove(newOwner);

            _nfts[nftAddr].remove(nftTokenId);
            // 如果 NFT 地址有 0 个 tokenId， 则从集合中移除 NFT
            if (_nfts[nftAddr].length() == 0) {
                _nftAddresses.remove(nftAddr);
                delete _nfts[nftAddr];
            }
        }

        // 将 NFT、TokenId 和金额从合约地址转移给新所有者
        erc1155.safeTransferFrom(
            address(this),
            newOwner,
            nftTokenId,
            amount,
            ""
        );

        emit WithdrawnNFT(nftAddr, nftTokenId, amount, newOwner);
    }

    /**
    * @notice 在内部更新 NFT 的所有权。 
    * @notice 调用者必须具有 ACL 标志：INTERNAL_TRANSFER 
    * @dev 如果 NFT 尚未在扩展内部拥有，则还原。 
    * @param fromOwner 当前所有者的地址。 
    * @param toOwner 新所有者的地址。 
    * @param nftAddr NFT 地址。 
    * @param nftTokenId NFT 令牌 ID。 
    * @param amount 特定 NFT 代币 ID 的数量。
    */
    function internalTransfer(
        DaoRegistry _dao,
        address fromOwner,
        address toOwner,
        address nftAddr,
        uint256 nftTokenId,
        uint256 amount
    ) external hasExtensionAccess(_dao, AclFlag.INTERNAL_TRANSFER) {
        // 检查代币数量是否有效且是否有足够的资金
        uint256 tokenAmount = _getTokenAmount(fromOwner, nftAddr, nftTokenId);
        require(
            amount > 0 && tokenAmount >= amount,
            "erc1155Ext::invalid amount"
        );

        // 检查扩展是否持有 NFT
        require(
            _nfts[nftAddr].contains(nftTokenId),
            "erc1155Ext::nft not found"
        );
        if (fromOwner != toOwner) {
            // 用当前余额 + 转账金额更新 toOwner 的内部记录
            uint256 toOwnerNewAmount = _getTokenAmount(
                toOwner,
                nftAddr,
                nftTokenId
            ) + amount;
            _updateTokenAmount(toOwner, nftAddr, nftTokenId, toOwnerNewAmount);
            // 用剩余金额更新 fromOwner 的内部记录
            _updateTokenAmount(
                fromOwner,
                nftAddr,
                nftTokenId,
                tokenAmount - amount
            );

            emit TransferredNFT(
                fromOwner,
                toOwner,
                nftAddr,
                nftTokenId,
                amount
            );
        }
    }

    /**
     * @notice Gets ID generated from an NFT address and token id (used internally to map ownership).
     * @param nftAddress The NFT address.
     * @param tokenId The NFT token id.
     */
    function getNFTId(address nftAddress, uint256 tokenId)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(nftAddress, tokenId));
    }

    /**
     * @notice gets owner's amount of a TokenId for an NFT address.
     * @param owner eth address
     * @param tokenAddr the NFT address.
     * @param tokenId The NFT token id.
     */
    function getNFTIdAmount(
        address owner,
        address tokenAddr,
        uint256 tokenId
    ) external view returns (uint256) {
        return _nftTracker[owner][tokenAddr][tokenId];
    }

    /**
     * @notice Returns the total amount of token ids collected for an NFT address.
     * @param tokenAddr The NFT address.
     */
    function nbNFTs(address tokenAddr) external view returns (uint256) {
        return _nfts[tokenAddr].length();
    }

    /**
     * @notice Returns token id associated with an NFT address stored in the GUILD collection at the specified index.
     * @param tokenAddr The NFT address.
     * @param index The index to get the token id if it exists.
     */
    function getNFT(address tokenAddr, uint256 index)
        external
        view
        returns (uint256)
    {
        return _nfts[tokenAddr].at(index);
    }

    /**
     * @notice Returns the total amount of NFT addresses collected.
     */
    function nbNFTAddresses() external view returns (uint256) {
        return _nftAddresses.length();
    }

    /**
     * @notice Returns NFT address stored in the GUILD collection at the specified index.
     * @param index The index to get the NFT address if it exists.
     */
    function getNFTAddress(uint256 index) external view returns (address) {
        return _nftAddresses.at(index);
    }

    /**
     * @notice Returns owner of NFT that has been transferred to the extension.
     * @param nftAddress The NFT address.
     * @param tokenId The NFT token id.
     */
    function getNFTOwner(
        address nftAddress,
        uint256 tokenId,
        uint256 index
    ) external view returns (address) {
        return _ownership[getNFTId(nftAddress, tokenId)].at(index);
    }

    /**
     * @notice Returns the total number of owners of an NFT addresses and token id collected.
     */
    function nbNFTOwners(address nftAddress, uint256 tokenId)
        external
        view
        returns (uint256)
    {
        return _ownership[getNFTId(nftAddress, tokenId)].length();
    }

    /**
     * @notice Helper function to update the extension states for an NFT collected by the extension.
     * @param nftAddr The NFT address.
     * @param nftTokenId The token id.
     * @param owner The address of the owner.
     * @param amount of the tokenID
     */
    function _saveNft(
        address nftAddr,
        uint256 nftTokenId,
        address owner,
        uint256 amount
    ) private {
        // Save the asset address and tokenId

        _nfts[nftAddr].add(nftTokenId);
        // Track the owner by nftAddr+tokenId

        _ownership[getNFTId(nftAddr, nftTokenId)].add(owner);
        // Keep track of the collected assets addresses

        _nftAddresses.add(nftAddr);
        // Track the actual owner per Token Id and amount
        uint256 currentAmount = _nftTracker[owner][nftAddr][nftTokenId];
        _nftTracker[owner][nftAddr][nftTokenId] = currentAmount + amount;
    }

    /**
     *  @notice required function from IERC1155 standard to be able to to receive tokens
     */
    function onERC1155Received(
        address,
        address,
        uint256 id,
        uint256 value,
        bytes calldata
    ) external override returns (bytes4) {
        _saveNft(msg.sender, id, DaoHelper.GUILD, value);
        return this.onERC1155Received.selector;
    }

    /**
     *  @notice required function from IERC1155 standard to be able to to batch receive tokens
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata
    ) external override returns (bytes4) {
        require(
            ids.length == values.length,
            "erc1155Ext::ids values length mismatch"
        );
        for (uint256 i = 0; i < ids.length; i++) {
            _saveNft(msg.sender, ids[i], DaoHelper.GUILD, values[i]);
        }

        return this.onERC1155Received.selector;
    }

    /**
     * @notice Supports ERC-165 & ERC-1155 interfaces only.
     * @dev https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1155.md
     */
    function supportsInterface(bytes4 interfaceID)
        external
        pure
        override
        returns (bool)
    {
        return
            interfaceID == 0x01ffc9a7 || // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
            interfaceID == 0x4e2312e0; // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
    }

    /**
     *  @notice internal function to update the amount of a tokenID for an NFT an owner has
     */
    function _updateTokenAmount(
        address owner,
        address nft,
        uint256 tokenId,
        uint256 amount
    ) internal {
        _nftTracker[owner][nft][tokenId] = amount;
    }

    /**
     *  @notice internal function to get the amount of a tokenID for an NFT an owner has
     */
    function _getTokenAmount(
        address owner,
        address nft,
        uint256 tokenId
    ) internal view returns (uint256) {
        return _nftTracker[owner][nft][tokenId];
    }
}
