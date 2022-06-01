// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IFinancing.sol";
import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "../adapters/interfaces/IVoting.sol";
import "../guards/AdapterGuard.sol";
import "./modifiers/Reimbursable.sol";
import "../helpers/DaoHelper.sol";

contract FinancingContract is IFinancing, AdapterGuard, Reimbursable {
    struct ProposalDetails {
        address applicant; // the proposal applicant address, can not be a reserved address
        uint256 amount; // the amount requested for funding
        address token; // the token address in which the funding must be sent to
    }

    // 跟踪每个 dao 处理的所有融资提案
    mapping(address => mapping(bytes32 => ProposalDetails)) public proposals;

    /**
    * @notice 创建并发起融资提案
    * @dev 申请人地址不得保留
    * @dev 令牌地址必须得到 DAO 银行的允许/支持
    * @dev 请求的金额必须大于零
    * @dev 只有 DAO 的成员才能发起融资提案
    * @param dao DAO 地址
    * @param proposalId 提案 ID
    * @param applicant 申请人地址
    * @param token 接收资金的代币
    * @param amount 所需的金额
    * @param data 有关融资提案的其他详细信息
    */

    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address applicant,
        address token,
        uint256 amount,
        bytes memory data
    ) external override reimbursable(dao) {
        require(amount > 0, "invalid requested amount");
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        require(bank.isTokenAllowed(token), "token not allowed");
        require(
            DaoHelper.isNotReservedAddress(applicant),
            "applicant using reserved address"
        );
        dao.submitProposal(proposalId);

        ProposalDetails storage proposal = proposals[address(dao)][proposalId];
        proposal.applicant = applicant;
        proposal.amount = amount;
        proposal.token = token;

        IVoting votingContract = IVoting(dao.getAdapterAddress(DaoHelper.VOTING));

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
      *
      * @notice 处理融资提案以授予所请求的资金
      * @dev 仅接受未处理的提案
      * @dev 仅接受赞助的提案 
      * @dev 只有通过的提案才能得到处理并释放资金 
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
        BankExtension bank = BankExtension(dao.getExtensionAddress(DaoHelper.BANK));

        bank.subtractFromBalance(
            dao,
            DaoHelper.GUILD,
            details.token,
            details.amount
        );
        bank.addToBalance(
            dao,
            details.applicant,
            details.token,
            details.amount
        );
    }
}
