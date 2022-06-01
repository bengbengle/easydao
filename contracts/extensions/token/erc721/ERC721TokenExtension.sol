// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "../../../core/DaoRegistry.sol";
import "../../../helpers/DaoHelper.sol";
import "../../IExtension.sol";
import "../../bank/Bank.sol";
import "../../../guards/AdapterGuard.sol";

contract ERC721TokenExtension is ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    Pausable,
    Ownable,
    ERC721Burnable,
    IExtension
{
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    bool private _initialized;

    DaoRegistry private _dao;

    constructor() ERC721("MyToken", "MTK") {}

     /**
     * @notice 用它所属的 DAO 初始化扩展 
     * @param dao 拥有扩展的 DAO 的地址
     */
    function initialize(DaoRegistry dao, address) external override {
        require(!_initialized, "vestingExt::already initialized");
        _initialized = true;
        _dao = dao;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function safeMint(address to, string memory uri) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal whenNotPaused override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }


    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}