pragma solidity ^0.8.0;


import "../../IFactory.sol";
import "../../../core/CloneFactory.sol";
import "./ERC721TokenExtension.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ERC721TokenExtensionFactory is IFactory, CloneFactory, ReentrancyGuard {
    
    address public identityAddress;

    event ERC721TokenExtensionCreated(
        address daoAddress,
        address extensionAddress
    );

    mapping(address => address) private _extensions;

    constructor(address _identityAddress) {
        require(
            _identityAddress != address(0x0), 
            "invalid addr"
        );
        identityAddress = _identityAddress;
    }

    /**
     * @notice Creates a clone of the ERC721 Token Extension.
     */
    function create(
        address dao
        // string calldata tokenName,
        // address tokenAddress,
        // string calldata tokenSymbol,
        // uint8 decimals
    ) external nonReentrant {
        require(dao != address(0x0), "invalid dao addr");
        address payable extensionAddr = _createClone(identityAddress);

        _extensions[dao] = extensionAddr;
        
        ERC721TokenExtension ext = ERC721TokenExtension(extensionAddr);
        // ext.setName(tokenName);
        // ext.setToken(tokenAddress);
        // ext.setSymbol(tokenSymbol);
        // ext.setDecimals(decimals);
        
        emit ERC721TokenExtensionCreated(dao, address(ext));
    }

    /**
     * @notice 返回为 DAO 的扩展地址， 如果不存在，则返回 0x0...
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
