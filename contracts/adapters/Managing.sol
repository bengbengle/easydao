pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "./interfaces/IManaging.sol";
import "../core/DaoRegistry.sol";
import "../adapters/interfaces/IVoting.sol";
import "../guards/AdapterGuard.sol";
import "./modifiers/Reimbursable.sol";
import "../helpers/DaoHelper.sol";

contract ManagingContract is IManaging, AdapterGuard, Reimbursable {
    // DAO => (ProposalID => ProposalDetails)
    mapping(address => mapping(bytes32 => ProposalDetails)) public proposals;
    // DAO => (ProposalId => Configuration[])
    mapping(address => mapping(bytes32 => Configuration[]))
        public configurations;

    /**
     * @notice 创建替换、删除或添加适配器的提议。
     * @dev 如果 adapterAddress 等于 0x0，adapterId 会从注册表中删除（如果可用）。
     * @dev 如果 adapterAddress 是保留地址，它会恢复。
     * @dev 键和值必须具有相同的长度。
     * @dev proposalId 不能重复使用。
     * @param dao dao 地址。
     * @param proposalId Tproposal 详细信息
     * @param proposal 提案详情
     * @param data 传递给投票合约并识别提交者的附加数据
     */

    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        ProposalDetails calldata proposal,
        Configuration[] memory configs,
        bytes calldata data
    ) external override reimbursable(dao) {
        require(
            proposal.keys.length == proposal.values.length,
            "must be an equal number of config keys and values"
        );

        require(
            proposal.extensionAddresses.length ==
                proposal.extensionAclFlags.length,
            "must be an equal number of extension addresses and acl"
        );

        require(
            DaoHelper.isNotReservedAddress(proposal.adapterOrExtensionAddr),
            "address is reserved"
        );

        dao.submitProposal(proposalId);

        proposals[address(dao)][proposalId] = proposal;

        Configuration[] storage newConfigs = configurations[address(dao)][
            proposalId
        ];
        for (uint256 i = 0; i < configs.length; i++) {
            Configuration memory config = configs[i];
            newConfigs.push(
                Configuration({
                    key: config.key,
                    configType: config.configType,
                    numericValue: config.numericValue,
                    addressValue: config.addressValue
                })
            );
        }

        IVoting votingContract = IVoting(
            dao.getAdapterAddress(DaoHelper.VOTING)
        );
        address senderAddress = votingContract.getSenderAddress(
            dao,
            address(this),
            data,
            msg.sender
        );

        dao.sponsorProposal(proposalId, senderAddress, address(votingContract));
        votingContract.startNewVotingForProposal(dao, proposalId, data);
    }

    /**
     * @notice 处理发起的提案。
     * @dev 只有成员才能处理提案。
     * @dev 仅当投票通过时，提案才会被处理。
     * @dev 当适配器地址已被使用并且它是适配器添加时恢复。
     * @dev 当扩展地址已被使用并且它是扩展添加时恢复。
     * @param dao dao 地址。
     * @param proposalId 提案 ID。
     */

    function processProposal(DaoRegistry dao, bytes32 proposalId)
        external
        override
        reimbursable(dao)
    {
        ProposalDetails memory proposal = proposals[address(dao)][proposalId];

        IVoting votingContract = IVoting(dao.votingAdapter(proposalId));
        require(address(votingContract) != address(0), "adapter not found");

        require(
            votingContract.voteResult(dao, proposalId) ==
                IVoting.VotingState.PASS,
            "proposal did not pass"
        );

        dao.processProposal(proposalId);
        if (proposal.updateType == UpdateType.ADAPTER) {
            dao.replaceAdapter(
                proposal.adapterOrExtensionId,
                proposal.adapterOrExtensionAddr,
                proposal.flags,
                proposal.keys,
                proposal.values
            );
        } else if (proposal.updateType == UpdateType.EXTENSION) {
            _replaceExtension(dao, proposal);
        } else {
            revert("unknown update type");
        }
        _grantExtensionAccess(dao, proposal);
        _saveDaoConfigurations(dao, proposalId);
    }

    /**
     * @notice 如果扩展已经注册，它会从 DAO 注册表中删除扩展。
     * @notice 如果提供了 adapterOrExtensionAddr，则新地址将作为新扩展添加到 DAO 注册表。
     */
    function _replaceExtension(DaoRegistry dao, ProposalDetails memory proposal)
        internal
    {
        if (dao.extensions(proposal.adapterOrExtensionId) != address(0x0)) {
            dao.removeExtension(proposal.adapterOrExtensionId);
        }

        if (proposal.adapterOrExtensionAddr != address(0x0)) {
            dao.addExtension(
                proposal.adapterOrExtensionId,
                IExtension(proposal.adapterOrExtensionAddr),
                // The creator of the extension must be set as the DAO owner,
                // which is stored at index 0 in the members storage.
                dao.getMemberAddress(0)
            );
        }
    }

    /**
     * @notice Saves to the DAO Registry the ACL Flag that grants the access to the given `extensionAddresses`
     */
    function _grantExtensionAccess(
        DaoRegistry dao,
        ProposalDetails memory proposal
    ) internal {
        for (uint256 i = 0; i < proposal.extensionAclFlags.length; i++) {
            // It is fine to execute the external call inside the loop
            // because it is calling the correct function in the dao contract
            // it won't be calling a fallback that always revert.
            dao.setAclToExtensionForAdapter(
                // It needs to be registered as extension
                proposal.extensionAddresses[i],
                // It needs to be registered as adapter
                proposal.adapterOrExtensionAddr,
                // Indicate which access level will be granted
                proposal.extensionAclFlags[i]
            );
        }
    }

    /**
     * @notice Saves the numeric/address configurations to the DAO registry
     */
    function _saveDaoConfigurations(DaoRegistry dao, bytes32 proposalId)
        internal
    {
        Configuration[] memory configs = configurations[address(dao)][
            proposalId
        ];

        for (uint256 i = 0; i < configs.length; i++) {
            Configuration memory config = configs[i];
            if (ConfigType.NUMERIC == config.configType) {
                // It is fine to execute the external call inside the loop
                // because it is calling the correct function in the dao contract
                // it won't be calling a fallback that always revert.
                dao.setConfiguration(config.key, config.numericValue);
            } else if (ConfigType.ADDRESS == config.configType) {
                // It is fine to execute the external call inside the loop
                // because it is calling the correct function in the dao contract
                // it won't be calling a fallback that always revert.
                dao.setAddressConfiguration(config.key, config.addressValue);
            }
        }
    }
}
