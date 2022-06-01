// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "../../../core/DaoRegistry.sol";
import "../../../helpers/DaoHelper.sol";
import "../../IExtension.sol";
import "../../bank/Bank.sol";
import "./IERC721TransferStrategy.sol";
import "../../../guards/AdapterGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/**
 * ERC721Extension 为 内部代币 units 提供 erc721 合约功能
 */
contract ERC721ExtensionEnumerable is AdapterGuard, IExtension, IERC721, IERC721Enumerable {
    using Address for address;
    using Strings for uint256;

    // 该扩展所属的 DAO 地址 
    DaoRegistry public dao;

    // 在 eip-1167 代理模式下 内部跟踪 部署
    bool public initialized = false;

    // 由 DAO 管理的用于跟踪 内部转账 的 代币地址
    address public tokenAddress;

    // DAO 管理的代币名称 
    string public tokenName;

    // 由 DAO 管理的代币的符号
    string public tokenSymbol;

    // DAO 管理的代币的小数位数
    uint8 public tokenDecimals;

    // Tracks all the token allowances: owner => spender => tokenId
    // mapping(address => mapping(address => uint256)) private _allowances;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // ERC 721 Mapping 
     // Mapping from token ID to approved address

    // Tracks ERC721Enumerable

    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;
    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;
    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;
    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;


    /// @notice 可克隆合约必须有一个空的构造函数
    constructor() {}

    /**
     * @notice 使用它所属的 DAO 初始化扩展 并检查是否设置了参数
     * @param _dao 拥有扩展的 DAO 的地址
     * @param creator DAO 和扩展的所有者， 也是 DAO 的成员  
     */
    function initialize(DaoRegistry _dao, address creator) external  {
        require(!initialized, "already initialized");
        require(_dao.isMember(creator), "not a member");
        require(tokenAddress != address(0x0), "missing token address");
        require(bytes(tokenName).length != 0, "missing token name");
        require(bytes(tokenSymbol).length != 0, "missing token symbol");
        initialized = true;
        dao = _dao;
    }

    /**
     * @dev 返回由跟踪内部传输的 DAO 管理的令牌地址。
     */
    function token() external view virtual returns (address) {
        return tokenAddress;
    }

    /**
     * @dev 如果扩展未初始化， 未保留且不为零，则设置令牌地址
     */
    function setToken(address _tokenAddress) external {
        // 是否预留
        bool not_reserved = DaoHelper.isNotReservedAddress(_tokenAddress);

        require(!initialized, "already initialized");
        require(_tokenAddress != address(0x0), "invalid token address");
        require(not_reserved, "token address already in use");

        tokenAddress = _tokenAddress;
    }

    /**
     * @dev 返回令牌的名称
     */
    function name() external view virtual returns (string memory) {
        return tokenName;
    }

    /**
     * @dev 如果扩展未初始化，则设置令牌的名称
     */
    function setName(string memory _name) external {
        require(!initialized, "already initialized");
        tokenName = _name;
    }

    /**
     * @dev 返回令牌的符号，通常是名称的较短版本
     */
    function symbol() external view virtual returns (string memory) {
        return tokenSymbol;
    }

    /**
     * @dev 如果扩展未初始化，则设置令牌符号
     */
    function setSymbol(string memory _symbol) external {
        require(!initialized, "already initialized");
        tokenSymbol = _symbol;
    }

    /**
     * @dev 返回用于获取其用户表示的小数位数 
     * 例如， 如果 `decimals` 等于 `2`， 则 `505` 代币的余额应该向用户显示为 `5,05` (`505 / 10 ** 2`)
     */
    function decimals() external view virtual returns (uint8) {
        return tokenDecimals;
    }

    /**
     * @dev 如果扩展未初始化，则设置标记小数
     */
    function setDecimals(uint8 _decimals) external {
        require(!initialized, "already initialized");
        tokenDecimals = _decimals;
    }

    /**
     * @dev 返回总令牌数量 `TOTAL`
     */
    function totalSupply() public view returns (uint256) {
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        return bank.balanceOf(DaoHelper.TOTAL, tokenAddress);
    }

    /**
     * @dev 返回某账户下 `account` 拥有的 代币数量
     */
    function balanceOf(address owner) public view returns (uint256) {
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        return bank.balanceOf(owner, tokenAddress);
    }

    /**
     * @dev 考虑 snapshot，返回 `account` 拥有的代币数量
     */
    function getPriorAmount(address account, uint256 snapshot)
        external
        view
       returns (uint256)
    {
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        return bank.getPriorAmount(account, tokenAddress, snapshot);
    }
 

    /**
     * @dev 将 `tokenId` 设置为 `to` 在调用者代币上的限额 
     * @param to 将减少单位的地址帐户
     * @param tokenId 从消费账户中减少的金额 
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) public reentrancyGuard(dao)
    {
        address senderAddr = dao.getAddressIfDelegated(msg.sender);

        require(dao.isMember(senderAddr), "sender is not a member");

        require(
            DaoHelper.isNotZeroAddress(senderAddr),
            "ERC721: approve from the zero address"
        );

        require(
            DaoHelper.isNotZeroAddress(to),
            "ERC721: approve to the zero address"
        );

        require(
            DaoHelper.isNotReservedAddress(to),
            "spender can not be a reserved address"
        );


        _approve(to, tokenId);

        emit Approval(senderAddr, to, tokenId);
    }

     /**
     * @dev See {IERC721-getApproved}.
     */
    // function getApproved(uint256 tokenId) public view virtual override returns (address) {
    //     require(_exists(tokenId), "ERC721: approved query for nonexistent token");

    //     return _tokenApprovals[tokenId];
    // }
    function getApproved(uint256 tokenId) public view virtual returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }
    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual {
        _setApprovalForAll(msg.sender, operator, approved);
    }



    /**
     * @dev 将 `tokenId` 令牌从调用者的账户转移到 `recipient`
     * @dev 传输操作遵循 ERC721_EXT_TRANSFER_TYPE 属性指定的 DAO 配置 
     * @param recipient 接收代币的地址帐户 
     * @param tokenId 代币的金额 
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 tokenId) public
    {
        address senderAddr = dao.getAddressIfDelegated(msg.sender);

        return transferFrom(senderAddr, recipient, tokenId);
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        return msg.sender;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");

        transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public {
        
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");

        transferFrom(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        
        address owner = ownerOf(tokenId);

        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    

    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        require(owner != operator, "ERC721: approve to caller");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return true;
    }

    /**
     * @dev 使用 allowance mechanism 将 `tokenId` 令牌从 `sender` 转移到 `recipient`。然后从 caller 的 "allowance" 扣除 "tokenId" 
     * @dev 传输操作遵循 ERC721_EXT_TRANSFER_TYPE 属性指定的 DAO 配置
     * @param sender 将减少 units 的地址帐户
     * @param recipient 将接收 units 的地址帐户 
     * @param tokenId 金额 
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 tokenId) public {

        require(DaoHelper.isNotZeroAddress(recipient), "ERC721: transfer to the zero address");

        address adapter = dao.getAdapterAddress(DaoHelper.TRANSFER_STRATEGY);

        IERC721TransferStrategy strategy = IERC721TransferStrategy(adapter);
        
        // allowedTokenId： 允许转账的金额
        // approvalType： 授权类型
        // (
        //     IERC721TransferStrategy.ApprovalType approvalType, uint256 allowedTokenId
        // ) = strategy.evaluateTransfer(
        //     dao,
        //     tokenAddress,
        //     sender,
        //     recipient,
        //     tokenId,
        //     msg.sender
        // );

        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        
        // address owner = _owners(tokenId);
        // require(
        //     sender == owner,
        //     "ERC721: transfer tokenId not approved"
        // );

        // not allowed
        // if (approvalType == IERC721TransferStrategy.ApprovalType.NONE) {
        //     revert("transfer not allowed");
        // }

        // // no limit
        // if (approvalType == IERC721TransferStrategy.ApprovalType.SPECIAL) {
        //     _transferInternal(sender, recipient, tokenId, bank);

        //     emit Transfer(sender, recipient, tokenId);
        //     // return true;
        // }
         _transferInternal(sender, recipient, tokenId, bank);

        emit Transfer(sender, recipient, tokenId);

    }
    
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    // 转移 内部代币
    // senderAddr 发送者
    // recipient 接收者
    // tokenId 金额
    // bank 金库
    function _transferInternal(address senderAddr, address recipient, uint256 tokenId, BankExtension bank) 
        internal 
    {
        _balances[senderAddr] -= 1;
        _balances[recipient] += 1;

        _owners[tokenId] = recipient;
        _approve(address(0), tokenId);


        DaoHelper.potentialNewMember(recipient, dao, bank);

        bank.internalTransfer(dao, senderAddr, recipient, tokenAddress, tokenId);
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }


    // IERC721Enumerable 

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual returns (uint256) {
        require(index < balanceOf(owner), "ERC721Enumerable: owner index out of bounds");
        return _ownedTokens[owner][index];
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint256 index) public view virtual returns (uint256) {
        require(index < totalSupply(), "ERC721Enumerable: global index out of bounds");
        return _allTokens[index];
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual  {
        // super._beforeTokenTransfer(from, to, tokenId);

        if (from == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (to != from) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = balanceOf(to);
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

         uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }


    function supportsInterface(bytes4 interfaceId)
        external
        pure
        
       returns (bool)
    {
        return
        this.transferFrom.selector == interfaceId || 
        this.approve.selector == interfaceId || 
        this.setApprovalForAll.selector == interfaceId || 
        this.tokenOfOwnerByIndex.selector == interfaceId ||
        type(IERC721Enumerable).interfaceId == interfaceId;   
    }
}
