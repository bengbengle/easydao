pragma solidity ^0.8.0;

import "../../core/CloneFactory.sol";
import "../IFactory.sol";
import "./ERC1271.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ERC1271ExtensionFactory is IFactory, CloneFactory, ReentrancyGuard {
    address public identityAddress;

    event ERC1271Created(address daoAddress, address extensionAddress);

    mapping(address => address) private _extensions;

    constructor(address _identityAddress) {
        require(_identityAddress != address(0x0), "invalid addr");
        identityAddress = _identityAddress;
    }

    /**
     * @notice 创建并初始化一个新的 ERC1271 Extension
     */
    function create(address dao) external nonReentrant {
        require(dao != address(0x0), "invalid dao addr");
        address extensionAddr = _createClone(identityAddress);
        _extensions[dao] = extensionAddr;
        ERC1271Extension erc1271 = ERC1271Extension(extensionAddr);
        emit ERC1271Created(dao, address(erc1271));
    }

    /**
     * @notice Returns the extension address created for that DAO, or 0x0... if it does not exist.
     * @notice 回为该 DAO 创建的扩展地址
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
