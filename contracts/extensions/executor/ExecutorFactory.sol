pragma solidity ^0.8.0;



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
     * @notice 创建并初始化一个新的 ERC1271 Extension
     */
    function create(address dao) external nonReentrant {
        require(dao != address(0x0), "invalid dao addr");
        address payable extensionAddr = _createClone(identityAddress);
        _extensions[dao] = extensionAddr;
        ExecutorExtension exec = ExecutorExtension(extensionAddr);
        emit ExecutorCreated(dao, address(exec));
    }

    /**
      * @notice 返回为该 DAO 创建的扩展地址，如果不存在，则返回 0x0...
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
