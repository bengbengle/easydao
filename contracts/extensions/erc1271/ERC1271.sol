pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/DaoRegistry.sol";
import "../IExtension.sol";
import "../../helpers/DaoHelper.sol";
import "../../guards/AdapterGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";

/**
MIT License

Copyright (c) 2020 Openlaw

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */

/**
 * @dev 签署任意消息并暴露 ERC1271 接口
 */
contract ERC1271Extension is IExtension, IERC1271 {
    bool public initialized = false; // internally tracks deployment under eip-1167 proxy pattern
    DaoRegistry public dao;

    enum AclFlag {
        SIGN
    }

    struct DAOSignature {
        bytes32 signatureHash;
        bytes4 magicValue;
    }

    mapping(bytes32 => DAOSignature) public signatures; // msgHash => Signature

    /// @notice 可克隆合约必须有一个空的构造函数
    constructor() {}

    modifier hasExtensionAccess(DaoRegistry _dao, AclFlag flag) {
        require(
            dao == _dao &&
                (address(this) == msg.sender ||
                    address(dao) == msg.sender ||
                    DaoHelper.isInCreationModeAndHasAccess(dao) ||
                    dao.hasAdapterAccessToExtension(
                        msg.sender,
                        address(this),
                        uint8(flag)
                    )),
            "erc1271::accessDenied"
        );
        _;
    }

    /**
     * @notice 初始化 ERC1271 扩展以与 DAO 关联，只能调用一次 
     * @param creator DAO 的创建者，他将成为初始成员
     */
    function initialize(DaoRegistry _dao, address creator) external override {
        require(!initialized, "erc1271::already initialized");
        require(_dao.isMember(creator), "erc1271::not member");
        initialized = true;
        dao = _dao;
    }

    /**
     * @notice 根据 permissionHash 验证是否存在签名，并检查提供的签名是否与 预期的 signatureHash 匹配。 
     * @param permissionHash 要签名的数据的摘要。 
     * @param signature 要编码、散列和验证的字节签名。 
     * @return 如果签名有效，则以字节 4 为单位的幻数，否则它会还原。
     */
    function isValidSignature(bytes32 permissionHash, bytes memory signature)
        external
        view
        override
        returns (bytes4)
    {
        DAOSignature memory daoSignature = signatures[permissionHash];
        require(daoSignature.magicValue != 0, "erc1271::invalid signature");
        require(
            daoSignature.signatureHash == keccak256(abi.encodePacked(signature)),
            "erc1271::invalid signature hash"
        );
        return daoSignature.magicValue;
    }

    /**
     * @notice 在扩展中注册一个有效的签名。 
     * @dev 只有带有 `SIGN` ACL 的适配器/扩展可以调用这个函数。 
     * @param permissionHash 要签名的数据的摘要。 
     * @param signatureHash 签名的哈希值。 
     * @param magicValue 成功时 ERC1271 接口返回的值。
     */
    function sign(
        DaoRegistry _dao,
        bytes32 permissionHash,
        bytes32 signatureHash,
        bytes4 magicValue
    ) external hasExtensionAccess(_dao, AclFlag.SIGN) {
        signatures[permissionHash] = DAOSignature({
            signatureHash: signatureHash,
            magicValue: magicValue
        });
    }
}
