pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT
import "../../core/DaoRegistry.sol";
import "../../core/CloneFactory.sol";
import "../IFactory.sol";
import "./ERC1155TokenExtension.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract ERC1155TokenCollectionFactory is
    IFactory,
    CloneFactory,
    ReentrancyGuard
{
    address public identityAddress;

    event ERC1155CollectionCreated(
        address daoAddress,
        address extensionAddress
    );

    mapping(address => address) private _extensions;

    constructor(address _identityAddress) {
        require(_identityAddress != address(0x0), "invalid addr");
        identityAddress = _identityAddress;
    }

    /**
     * @notice Create and initialize a new Standard NFT Extension which is based on ERC1155
     */
    function create(address dao) external nonReentrant {
        require(dao != address(0x0), "invalid dao addr");
        address extensionAddr = _createClone(identityAddress);
        _extensions[dao] = extensionAddr;
        ERC1155TokenExtension extension = ERC1155TokenExtension(extensionAddr);
        emit ERC1155CollectionCreated(dao, address(extension));
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
