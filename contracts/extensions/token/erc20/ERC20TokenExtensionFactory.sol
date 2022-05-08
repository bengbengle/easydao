pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT
import "../../../core/DaoRegistry.sol";
import "../../../core/CloneFactory.sol";
import "../../IFactory.sol";
import "./ERC20TokenExtension.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ERC20TokenExtensionFactory is IFactory, CloneFactory, ReentrancyGuard {
    address public identityAddress;

    event ERC20TokenExtensionCreated(
        address daoAddress,
        address extensionAddress
    );

    mapping(address => address) private _extensions;

    constructor(address _identityAddress) {
        require(_identityAddress != address(0x0), "invalid addr");
        identityAddress = _identityAddress;
    }

    /**
     * @notice Creates a clone of the ERC20 Token Extension.
     */
    function create(
        address dao,
        string calldata tokenName,
        address tokenAddress,
        string calldata tokenSymbol,
        uint8 decimals
    ) external nonReentrant {
        require(dao != address(0x0), "invalid dao addr");
        address payable extensionAddr = _createClone(identityAddress);
        _extensions[dao] = extensionAddr;
        ERC20Extension ext = ERC20Extension(extensionAddr);
        ext.setName(tokenName);
        ext.setToken(tokenAddress);
        ext.setSymbol(tokenSymbol);
        ext.setDecimals(decimals);
        emit ERC20TokenExtensionCreated(dao, address(ext));
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
