pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT
import "./DaoRegistry.sol";
import "./CloneFactory.sol";


contract DaoFactory is CloneFactory {
    struct Adapter {
        bytes32 id;
        address addr;
        uint128 flags;
    }

    // daoAddr => hashedName
    mapping(address => bytes32) public daos;
    // hashedName => daoAddr
    mapping(bytes32 => address) public addresses;

    address public identityAddress;

    /**
     * @notice Event emitted when a new DAO has been created.
     * @param _address The DAO address.
     * @param _name The DAO name.
     */
    event DAOCreated(address _address, string _name);

    constructor(address _identityAddress) {
        require(_identityAddress != address(0x0), "invalid addr");
        identityAddress = _identityAddress;
    }

    /**
     * @notice Creates and initializes a new DaoRegistry with the DAO creator and the transaction sender.
     * @notice Enters the new DaoRegistry in the DaoFactory state.
     * @dev The daoName must not already have been taken.
     * @param daoName The name of the DAO which, after being hashed, is used to access the address.
     * @param creator The DAO's creator, who will be an initial member.
     */
    function createDao(string calldata daoName, address creator) external {
        bytes32 hashedName = keccak256(abi.encode(daoName));
        require(
            addresses[hashedName] == address(0x0),
            string(abi.encodePacked("name ", daoName, " already taken"))
        );
        DaoRegistry dao = DaoRegistry(_createClone(identityAddress));

        address daoAddr = address(dao);
        addresses[hashedName] = daoAddr;
        daos[daoAddr] = hashedName;

        dao.initialize(creator, msg.sender);
         
        emit DAOCreated(daoAddr, daoName);
    }

    /**
     * @notice Returns the DAO address based on its name.
     * @return The address of a DAO, given its name.
     * @param daoName Name of the DAO to be searched.
     */
    function getDaoAddress(string calldata daoName)
        external
        view
        returns (address)
    {
        return addresses[keccak256(abi.encode(daoName))];
    }

    /**
     * @notice Adds adapters and sets their ACL for DaoRegistry functions.
     * @dev A new DAO is instantiated with only the Core Modules enabled, to reduce the call cost. This call must be made to add adapters.
     * @dev The message sender must be an active member of the DAO.
     * @dev The DAO must be in `CREATION` state.
     * @param dao DaoRegistry to have adapters added to.
     * @param adapters Adapter structs to be added to the DAO.
     * @notice 为 DaoRegistry 函数添加适配器并设置它们的 ACL。 
     * @dev 一个新的 DAO 仅在启用核心模块的情况下实例化，以降低调用成本。必须进行此调用以添加适配器。 * @dev 消息发送者必须是 DAO 的活跃成员。 * @dev DAO 必须处于 `CREATION` 状态。 * @param dao DaoRegistry 添加适配器。 
     * @param adapters 要添加到 DAO 的适配器结构
     */
    function addAdapters(DaoRegistry dao, Adapter[] calldata adapters)
        external
    {
        require(dao.isMember(msg.sender), "not member");
        // Registring Adapters
        require(dao.state() == DaoRegistry.DaoState.CREATION, "this DAO has already been setup");

        for (uint256 i = 0; i < adapters.length; i++) {
             
            dao.replaceAdapter(
                adapters[i].id,
                adapters[i].addr,
                adapters[i].flags,
                new bytes32[](0),
                new uint256[](0)
            );
        }
    }

    /**
     * @notice Configures extension to set the ACL for each adapter that needs to access the extension.
     * @dev The message sender must be an active member of the DAO.
     * @dev The DAO must be in `CREATION` state.
     * @param dao DaoRegistry for which the extension is being configured.
     * @param extension The address of the extension to be configured.
     * @param adapters Adapter structs for which the ACL is being set for the extension.
     */
    function configureExtension(
        DaoRegistry dao,
        address extension,
        Adapter[] calldata adapters
    ) external {
        require(dao.isMember(msg.sender), "not member");
        //Registring Adapters
        require(
            dao.state() == DaoRegistry.DaoState.CREATION,
            "this DAO has already been setup"
        );

        for (uint256 i = 0; i < adapters.length; i++) {
             
            dao.setAclToExtensionForAdapter(
                extension,
                adapters[i].addr,
                adapters[i].flags
            );
        }
    }

    /**
     * @notice Removes an adapter with a given ID from a DAO, and adds a new one of the same ID.
     * @dev The message sender must be an active member of the DAO.
     * @dev The DAO must be in `CREATION` state.
     * @param dao DAO to be updated.
     * @param adapter Adapter that will be replacing the currently-existing adapter of the same ID.
     */
    function updateAdapter(DaoRegistry dao, Adapter calldata adapter) external {
        require(dao.isMember(msg.sender), "not member");
        require(
            dao.state() == DaoRegistry.DaoState.CREATION,
            "this DAO has already been setup"
        );

        dao.replaceAdapter(
            adapter.id,
            adapter.addr,
            adapter.flags,
            new bytes32[](0),
            new uint256[](0)
        );
    }
}
