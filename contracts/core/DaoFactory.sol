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
     * @notice 创建新 DAO 时发出的事件
     * @param _address DAO 地址
     * @param _name DAO 名称
     */
    event DAOCreated(address _address, string _name);

    constructor(address _identityAddress) {
        require(_identityAddress != address(0x0), "invalid addr");
        identityAddress = _identityAddress;
    }

    /**
     * @notice 使用 DAO 创建者和交易发送者 创建并初始化 一个新的 DaoRegistry
     * @notice 在 DaoFactory 状态下进入新的 DaoRegistry
     * @dev daoName 必须尚未被占用
     * @param daoName DAO 的名称，经过哈希处理后，用于访问地址
     * @param creator DAO 的创建者，他将成为初始成员
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

    /*** 
     * @notice 根据名称返回 DAO 地址  
     * @return 一个 DAO 的地址，给定它的名字  
     * @param daoName 要搜索的 DAO 的名称 
     */
    function getDaoAddress(string calldata daoName)
        external
        view
        returns (address)
    {
        return addresses[keccak256(abi.encode(daoName))];
    }

    /**
    * @notice 配置扩展为需要访问扩展的每个适配器设置 ACL  
    * @dev 消息发送者必须是 DAO 的活跃成员  
    * @dev DAO 必须处于 `CREATION` 状态  
    * @param dao DaoRegistry 正在为其配置扩展  
    * @param extension 要配置的扩展地址  
    * @param adapters 为扩展设置 ACL 的适配器结构 
    */
    function configureExtension(
        DaoRegistry dao,
        address extension,
        Adapter[] calldata adapters
    ) external {
        require(dao.isMember(msg.sender), "not member");
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
     * @notice 为 DaoRegistry 函数添加适配器并设置它们的 ACL  
     * @dev 一个新的 DAO 仅在启用核心模块的情况下实例化，以降低调用成本 必须进行此调用以添加适配器  
     * @dev 消息发送者必须是 DAO 的活跃成员  
     * @dev DAO 必须处于 `CREATION` 状态  
     * @param dao DaoRegistry 添加适配器  
     * @param adapters 要添加到 DAO 的适配器结构
     */
    function addAdapters(DaoRegistry dao, Adapter[] calldata adapters)
        external
    {
        require(dao.isMember(msg.sender), "not member");
        require(
            dao.state() == DaoRegistry.DaoState.CREATION,
            "this DAO has already been setup"
        );

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
     * @notice 从 DAO 中删除具有给定 ID 的适配器，并添加一个具有相同 ID 的新适配器
     * @dev 消息发送者必须是 DAO 的活跃成员
     * @dev DAO 必须处于 `CREATION` 状态
     * @param dao DAO 待更新
     * @param adapter 将替换当前存在的具有相同 ID 的适配器的适配器
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
