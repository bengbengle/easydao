pragma solidity ^0.8.0;



import "../../core/DaoRegistry.sol";

interface IManaging {
    // 未知， 适配器， 扩展
    enum UpdateType {
        UNKNOWN,
        ADAPTER,
        EXTENSION
    }
    // 数字, 地址
    enum ConfigType {
        NUMERIC,
        ADDRESS
    }
    // configType
    struct Configuration {
        bytes32 key;
        uint256 numericValue;
        address addressValue;
        ConfigType configType;
    }

    struct ProposalDetails {
        bytes32 adapterOrExtensionId;
        address adapterOrExtensionAddr;
        UpdateType updateType;
        uint128 flags;
        bytes32[] keys;
        uint256[] values;
        address[] extensionAddresses;
        uint128[] extensionAclFlags;
    }

    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        ProposalDetails calldata proposal,
        Configuration[] memory configs,
        bytes calldata data
    ) external;

    function processProposal(DaoRegistry dao, bytes32 proposalId) external;
}
