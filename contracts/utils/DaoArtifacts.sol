pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract DaoArtifacts is Ownable {
    // Types of artifacts that can be stored in this contract
    // 可以存储在此合约中的工件类型
    enum ArtifactType {
        CORE,
        FACTORY,
        EXTENSION,
        ADAPTER,
        UTIL
    }

    // Mapping from Artifact Name => (Owner Address => (Type => (Version => Adapters Address)))
    mapping(bytes32 => mapping(address => mapping(ArtifactType => mapping(bytes32 => address))))
        public artifacts;

    struct Artifact {
        bytes32 _id;
        address _owner;
        bytes32 _version;
        address _address;
        ArtifactType _type;
    }

    event NewArtifact(
        bytes32 _id,
        address _owner,
        bytes32 _version,
        address _address,
        ArtifactType _type
    );

    /**
     * @notice 将适配器地址添加到存储中 
     * @param _id 适配器的 id (sha3)  
     * @param _version 适配器的版本  
     * @param _address 要存储的适配器的地址  
     * @param _type 工件类型：0 = Core，1 = Factory，2 = Extension，3 = Adapter，4 = Util
     */
    function addArtifact(
        bytes32 _id,
        bytes32 _version,
        address _address,
        ArtifactType _type
    ) external {
        address _owner = msg.sender;
        artifacts[_id][_owner][_type][_version] = _address;
        emit NewArtifact(_id, _owner, _version, _address, _type);
    }

    /**
     * @notice 从存储中检索适配器/扩展工厂地址  
     * @param _id 适配器/扩展工厂 (sha3) 的 id  
     * @param _owner 适配器/扩展工厂所有者的地址  
     * @param _version 适配器/扩展工厂的版本  
     * @param _type 工件的类型：0 = 核心，1 = 工厂，2 = 扩展，3 = 适配器，4 = 实用程序  
     * @return 适配器/扩展工厂的地址（如果有） 
     */
    function getArtifactAddress(
        bytes32 _id,
        address _owner,
        bytes32 _version,
        ArtifactType _type
    ) external view returns (address) {
        return artifacts[_id][_owner][_type][_version];
    }

    /**
     * @notice 更新存储中的适配器/扩展工厂地址  
     * @notice 每个事务最多更新 20 个工件， 只允许合约的所有者执行批量更新  
     * @param _artifacts 要更新的工件数组 
     */
    function updateArtifacts(Artifact[] memory _artifacts) external onlyOwner {
        require(_artifacts.length <= 20, "Maximum artifacts limit exceeded");

        for (uint256 i = 0; i < _artifacts.length; i++) {
            Artifact memory a = _artifacts[i];
            artifacts[a._id][a._owner][a._type][a._version] = a._address;
        }
    }
}
