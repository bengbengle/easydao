// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ISignatures.sol";
import "../core/DaoRegistry.sol";
import "../extensions/erc1271/ERC1271.sol";
import "../adapters/interfaces/IVoting.sol";
import "../guards/AdapterGuard.sol";
import "./modifiers/Reimbursable.sol";
import "../helpers/DaoHelper.sol";

contract SignaturesContract is ISignatures, AdapterGuard, Reimbursable {
    
    struct ProposalDetails {
        bytes32 permissionHash;
        bytes32 signatureHash;
        bytes4 magicValue;
    }

    // 跟踪每个 dao 处理的所有签名提案
    mapping(address => mapping(bytes32 => ProposalDetails)) public proposals;

    /**
     * @notice 创建并赞助签名提案
     * @dev 只有 DAO 的成员才能发起签名提案
     * @param dao DAO 地址
     * @param proposalId 提案 ID
     * @param permissionHash 要签名的数据的哈希 
     * @param signatureHash 要标记为有效的签名的哈希 
     * @param magicValue 签名有效时返回的值 
     * @param data 有关签名提议的其他详细信息     
     */
    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        bytes32 permissionHash,
        bytes32 signatureHash,
        bytes4 magicValue,
        bytes memory data
    ) external override reimbursable(dao) {
        dao.submitProposal(proposalId);

        ProposalDetails storage proposal = proposals[address(dao)][proposalId];
        proposal.permissionHash = permissionHash;
        proposal.signatureHash = signatureHash;
        proposal.magicValue = magicValue;

        IVoting votingContract = IVoting(
            dao.getAdapterAddress(DaoHelper.VOTING)
        );
        address sponsoredBy = votingContract.getSenderAddress(
            dao,
            address(this),
            data,
            msg.sender
        );

        dao.sponsorProposal(proposalId, sponsoredBy, address(votingContract));
        votingContract.startNewVotingForProposal(dao, proposalId, data);
    }

    /**
    * @notice 处理签名提案以将数据标记为有效 
    * @dev 仅接受未处理的提案 
    * @dev 仅接受赞助的提案
    * @dev 只有通过的提案才能得到处理 
    * @param dao DAO 地址 
    * @param proposalId 提案 ID
     */
    function processProposal(DaoRegistry dao, bytes32 proposalId)
        external
        override
        reimbursable(dao)
    {
        ProposalDetails memory details = proposals[address(dao)][proposalId];

        IVoting votingContract = IVoting(dao.votingAdapter(proposalId));
        require(address(votingContract) != address(0), "adapter not found");

        require(
            votingContract.voteResult(dao, proposalId) == IVoting.VotingState.PASS,
            "proposal needs to pass"
        );
        dao.processProposal(proposalId);
        ERC1271Extension erc1271 = ERC1271Extension(
            dao.getExtensionAddress(DaoHelper.ERC1271)
        );

        erc1271.sign(dao, details.permissionHash, details.signatureHash, details.magicValue);
    }
}
