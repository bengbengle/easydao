pragma solidity ^0.8.0;



import "../../core/DaoRegistry.sol";
import "../IExtension.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract NFTExtension is IExtension, IERC721Receiver {
    // Add the library methods
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    bool public initialized = false; // internally tracks deployment under eip-1167 proxy pattern
    DaoRegistry public dao;

    enum AclFlag {
        WITHDRAW_NFT,
        COLLECT_NFT,
        INTERNAL_TRANSFER
    }

    event CollectedNFT(address nftAddr, uint256 nftTokenId);
    event TransferredNFT(
        address nftAddr,
        uint256 nftTokenId,
        address oldOwner,
        address newOwner
    );
    event WithdrawnNFT(address nftAddr, uint256 nftTokenId, address toAddress);

    // GUILD 集合中存储的 属于某个 NFT 地址 的所有 Token ID
    mapping(address => EnumerableSet.UintSet) private _nfts;

    // 已转移到 扩展的 NFT 记录的内部所有者
    mapping(bytes32 => address) private _ownership;

    // 收集并存储在 GUILD 集合中的所有 NFT 地址
    EnumerableSet.AddressSet private _nftAddresses;

    modifier hasExtensionAccess(DaoRegistry _dao, AclFlag flag) {
        require(
            dao == _dao && (DaoHelper.isInCreationModeAndHasAccess(dao) || dao.hasAdapterAccessToExtension(msg.sender, address(this), uint8(flag))),
            "erc721::accessDenied"
        );
        _;
    }

    /// @notice Clonable contract must have an empty constructor
    constructor() {}

    /**
     * @notice 用它所属的 DAO 地址初始化扩展
     * @param _dao 拥有扩展的 DAO 的地址
     * @param creator DAO 和 扩展的所有者，也是 DAO 的成员
     */
    function initialize(DaoRegistry _dao, address creator) external override {
        require(!initialized, "erc721::already initialized");
        require(_dao.isMember(creator), "erc721::not a member");

        initialized = true;
        dao = _dao;
    }

    /**
     * @notice 从所有者那里收集 NFT 并将其移动到 NFT 扩展
     * @notice {approve} 或 {setApprovalForAll} 必须允许移动此令牌
     * @dev 如果 NFT 不在 ERC721 标准中，则恢复
     * @param nftAddr NFT 合约地址
     * @param nftTokenId NFT 令牌 ID
     */

    function collect(
        DaoRegistry _dao,
        address nftAddr,
        uint256 nftTokenId
    ) external hasExtensionAccess(_dao, AclFlag.COLLECT_NFT) {
        IERC721 erc721 = IERC721(nftAddr);

        // 将 NFT 移动到合约地址
        address currentOwner = erc721.ownerOf(nftTokenId);
        if (currentOwner != address(this)) {
            erc721.safeTransferFrom(currentOwner, address(this), nftTokenId);
        }

        _saveNft(nftAddr, nftTokenId, DaoHelper.GUILD);
        emit CollectedNFT(nftAddr, nftTokenId);
    }

    /**
     * @notice 将 NFT 代币从 extension 地址转移给新的所有者
     * @notice 它还更新内部状态以跟踪扩展收集的所有 NFT
     * @notice 调用者必须有 ACL 标志： WITHDRAW_NFT
     * @notice TODO 需要从一个新的适配器 (RagequitNFT) 调用此函数，该适配器将管理银行余额，并将 NFT 返还给所有者
     * @dev 如果 NFT 不在 ERC721 标准中，则恢复
     * @param newOwner 新所有者的地址
     * @param nftAddr 必须符合 ERC721 标准的 NFT 地址
     * @param nftTokenId NFT 令牌 ID
     */
    function withdrawNFT(
        DaoRegistry _dao,
        address newOwner,
        address nftAddr,
        uint256 nftTokenId
    ) external hasExtensionAccess(_dao, AclFlag.WITHDRAW_NFT) {
        
        // 将 NFT 从合约地址中取出给实际拥有者
        require(
            _nfts[nftAddr].remove(nftTokenId),
            "erc721::can not remove token id"
        );

        IERC721 erc721 = IERC721(nftAddr);

        erc721.safeTransferFrom(address(this), newOwner, nftTokenId);

        // 从扩展中删除资产
        delete _ownership[getNFTId(nftAddr, nftTokenId)];

        // 如果我们不再持有该地址的资产，我们可以将其移除
        if (_nfts[nftAddr].length() == 0) {
            _nftAddresses.remove(nftAddr);
            // require(_nftAddresses.remove(nftAddr), "erc721::can not remove nft");
        }

        emit WithdrawnNFT(nftAddr, nftTokenId, newOwner);
    }

    /**
     * @notice 在内部更新 NFT 的所有权
     * @notice 调用者必须有 ACL 标志：INTERNAL_TRANSFER
     * @dev 如果 NFT 尚未在扩展内部拥有，则还原
     * @param nftAddr NFT 地址
     * @param nftTokenId NFT 令牌 ID
     * @param newOwner 新所有者的地址
     */
    function internalTransfer(
        DaoRegistry _dao,
        address nftAddr,
        uint256 nftTokenId,
        address newOwner
    ) external hasExtensionAccess(_dao, AclFlag.INTERNAL_TRANSFER) {
        require(newOwner != address(0x0), "erc721::new owner is 0");
        address currentOwner = _ownership[getNFTId(nftAddr, nftTokenId)];
        require(currentOwner != address(0x0), "erc721::nft not found");

        _ownership[getNFTId(nftAddr, nftTokenId)] = newOwner;

        emit TransferredNFT(nftAddr, nftTokenId, currentOwner, newOwner);
    }

    /**
     * @notice 获取从 NFT 地址和令牌 ID 生成的 ID（内部用于映射所有权）
     * @param nftAddress NFT 地址
     * @param tokenId NFT 代币 ID
     */
    function getNFTId(address nftAddress, uint256 tokenId)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(nftAddress, tokenId));
    }

    /**
     * @notice 返回为 NFT 地址收集的代币 ID 总数
     * @param tokenAddr NFT 地址
     */
    function nbNFTs(address tokenAddr) external view returns (uint256) {
        return _nfts[tokenAddr].length();
    }

    /**
     * @notice 返回与存储在指定索引处的 GUILD 集合中的 NFT 地址关联的令牌 ID
     * @param tokenAddr NFT 地址
     * @param index 获取令牌 ID（如果存在）的索引
     */
    function getNFT(address tokenAddr, uint256 index)
        external
        view
        returns (uint256)
    {
        return _nfts[tokenAddr].at(index);
    }

    /**
     * @notice 返回收集的 NFT 地址总数
     */
    function nbNFTAddresses() external view returns (uint256) {
        return _nftAddresses.length();
    }

    /**
     * @notice 返回存储在 GUILD 集合 中 指定索引处的 NFT 地址
     * @param index 获取 NFT 地址（如果存在）的索引
     */
    function getNFTAddress(uint256 index) external view returns (address) {
        return _nftAddresses.at(index);
    }

    /**
     * @notice 获取 guild 中 NFT 的拥有者
     * @param nftAddress NFT 地址
     * @param tokenId NFT 代币 ID
     */
    function getNFTOwner(address nftAddress, uint256 tokenId)
        external
        view
        returns (address)
    {
        return _ownership[getNFTId(nftAddress, tokenId)];
    }

    /**
     * @notice IERC721 标准所需的功能，以便能够将资产接收到此合约地址， 此处的 msg.sender 就是 nft 合约地址 nft addr
     */
    function onERC721Received(
        address,
        address,
        uint256 id,
        bytes calldata
    ) external override returns (bytes4) {
        _saveNft(msg.sender, id, DaoHelper.GUILD);

        return this.onERC721Received.selector;
    }

    /**
     * @notice Helper 函数用于更新 扩展收集 的 NFT 的扩展状态
     * @param nftAddr NFT 地址
     * @param nftTokenId 令牌 ID
     * @param owner 所有者的地址
     */
    function _saveNft(
        address nftAddr,
        uint256 nftTokenId,
        address owner
    ) private {
        // 保存资产，如果已保存则返回 false
        bool saved = _nfts[nftAddr].add(nftTokenId);
        if (saved) {
            // 设置 GUILD 的所有权
            _ownership[getNFTId(nftAddr, nftTokenId)] = owner;
            // 跟踪收集的资产
            require(_nftAddresses.add(nftAddr), "erc721::can not add nft");
        }
    }
}
