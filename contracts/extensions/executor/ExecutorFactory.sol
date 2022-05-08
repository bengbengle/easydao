pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/DaoRegistry.sol";
import "../../core/CloneFactory.sol";
import "../IFactory.sol";
import "./Executor.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ExecutorExtensionFactory is IFactory, CloneFactory, ReentrancyGuard {
    address public identityAddress;

    event ExecutorCreated(address daoAddress, address extensionAddress);

    mapping(address => address) private _extensions;

    constructor(address _identityAddress) {
        require(_identityAddress != address(0x0), "invalid addr");
        identityAddress = _identityAddress;
    }

    /**
     * @notice Create and initialize a new Executor Extension
     */
    function create(address dao) external nonReentrant {
        require(dao != address(0x0), "invalid dao addr");
        address payable extensionAddr = _createClone(identityAddress);
        _extensions[dao] = extensionAddr;
        ExecutorExtension exec = ExecutorExtension(extensionAddr);
        emit ExecutorCreated(dao, address(exec));
    }

    /**
     * @notice Returns the extension address created for that DAO, or 0x0... if it does not exist.
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
