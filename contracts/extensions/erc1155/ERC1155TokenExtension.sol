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
    * @notice ??? NFT ???????????????????????????????????????????????? 
    * @notice ?????????????????????????????????????????????????????? NFT??? 
    * @notice ????????????????????? ACL ????????? WITHDRAW_NFT 
    * @notice ?????????????????????????????????????????????????????? (RagequitNFT) ??????????????? NFT ????????????????????? 
    * @dev ?????? NFT ?????? ERC1155 ???????????????????????? 
    * @param newOwner ????????? NFT ??????????????????????????? 
    * @param nftAddr ???????????? ERC1155 ????????? NFT ????????? 
    * @param nftTokenId NFT ?????? ID??? 
    * @param amount ???????????? NFT ?????? ID ?????????     
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

        // ?????? tokenID ???????????????????????????
        _updateTokenAmount(from, nftAddr, nftTokenId, remainingAmount);

        uint256 ownerTokenIdBalance = erc1155.balanceOf(
            address(this),
            nftTokenId
        ) - amount;

        // ?????? Extension ?????? tokenId ????????? 0?????????????????? 
        // ???????????? GUILD/Extension ??????????????? token id???    
        if (ownerTokenIdBalance == 0) {
            delete _nftTracker[newOwner][nftAddr][nftTokenId];

            _ownership[getNFTId(nftAddr, nftTokenId)].remove(newOwner);

            _nfts[nftAddr].remove(nftTokenId);
            // ?????? NFT ????????? 0 ??? tokenId??? ????????????????????? NFT
            if (_nfts[nftAddr].length() == 0) {
                _nftAddresses.remove(nftAddr);
                delete _nfts[nftAddr];
            }
        }

        // ??? NFT???TokenId ?????????????????????????????????????????????
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
    * @notice ??????????????? NFT ??????????????? 
    * @notice ????????????????????? ACL ?????????INTERNAL_TRANSFER 
    * @dev ?????? NFT ?????????????????????????????????????????? 
    * @param fromOwner ??????????????????????????? 
    * @param toOwner ???????????????????????? 
    * @param nftAddr NFT ????????? 
    * @param nftTokenId NFT ?????? ID??? 
    * @param amount ?????? NFT ?????? ID ????????????
    */
    function internalTransfer(
        DaoRegistry _dao,
        address fromOwner,
        address toOwner,
        address nftAddr,
        uint256 nftTokenId,
        uint256 amount
    ) external hasExtensionAccess(_dao, AclFlag.INTERNAL_TRANSFER) {
        // ?????????????????????????????????????????????????????????
        uint256 tokenAmount = _getTokenAmount(fromOwner, nftAddr, nftTokenId);
        require(
            amount > 0 && tokenAmount >= amount,
            "erc1155Ext::invalid amount"
        );

        // ???????????????????????? NFT
        require(
            _nfts[nftAddr].contains(nftTokenId),
            "erc1155Ext::nft not found"
        );
        if (fromOwner != toOwner) {
            // ??????????????? + ?????????????????? toOwner ???????????????
            uint256 toOwnerNewAmount = _getTokenAmount(
                toOwner,
                nftAddr,
                nftTokenId
            ) + amount;
            _updateTokenAmount(toOwner, nftAddr, nftTokenId, toOwnerNewAmount);
            // ????????????????????? fromOwner ???????????????
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
