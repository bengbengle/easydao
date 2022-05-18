pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/CloneFactory.sol";
import "../IFactory.sol";
import "./Bank.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BankFactory is IFactory, CloneFactory, ReentrancyGuard {
    
    address public identityAddress;

    event BankCreated(address daoAddress, address extensionAddress);

    // dao addr --> ext addr
    mapping(address => address) private _extensions;

    constructor(address _identityAddress) {
        require(_identityAddress != address(0x0), "invalid addr");
        identityAddress = _identityAddress;
    }

    /**
     * @notice 创建并初始化一个新的 BankExtension
     * @param maxExternalTokens 银行中存储的 Extension 代币的最大数量
     */
    function create(address dao, uint8 maxExternalTokens)
        external
        nonReentrant
    {
        require(dao != address(0x0), "invalid dao addr");
        address extensionAddr = _createClone(identityAddress);
        _extensions[dao] = extensionAddr;
        BankExtension bank = BankExtension(extensionAddr);
        bank.setMaxExternalTokens(maxExternalTokens);
        emit BankCreated(dao, address(bank));
    }

    /**
     * @notice 返回为该 DAO 创建的 扩展地址， 如果不存在，则返回 0x0...
     */
    function getExtensionAddress(address dao)
        external
        view
        override
        returns (address)
    {
        return _extensions[dao];
    }
}
