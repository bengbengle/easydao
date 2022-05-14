pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "../helpers/DaoHelper.sol";
import "../adapters/interfaces/IVoting.sol";
import "./modifiers/Reimbursable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TributeContract is Reimbursable, AdapterGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    struct ProposalDetails {
        // The proposal id.
        bytes32 id;
        // The applicant address (who will receive the DAO internal tokens and
        // become a member; this address may be different than the actual owner
        // of the ERC-20 tokens being provided as tribute).
        // 申请者地址（将收到 DAO 内部代币并成为成员；此地址可能与作为贡品的 ERC-20 代币的实际所有者不同
        address applicant;
        // The address of the DAO internal token to be minted to the applicant.
        // 要铸造给申请人的 DAO 内部代币的地址 
        address tokenToMint;
        // The amount requested of DAO internal tokens.
        uint256 requestAmount;
        // The address of the ERC-20 tokens that will be transferred to the DAO
        // in exchange for DAO internal tokens.
        address token;
        // The amount of tribute tokens.
        uint256 tributeAmount;
        // The owner of the ERC-20 tokens being provided as tribute.
        address tributeTokenOwner;
    }

    // Keeps track of all tribute proposals handled by each DAO.
    // 跟踪每个 DAO 处理的所有致敬提案
    mapping(address => mapping(bytes32 => ProposalDetails)) public proposals;

    /**
     * @notice Configures the adapter for a particular DAO.
     * @notice Registers the DAO internal token with the DAO Bank.
     * @dev Only adapters registered to the DAO can execute the function call (or if the DAO is in creation mode).
     * @dev A DAO Bank extension must exist and be configured with proper access for this adapter.
     * @param dao The DAO address.
     * @param tokenAddrToMint The internal token address to be registered with the DAO Bank.
     * @param tokenAddrToMint 要在 DAO 银行注册的内部代币地址 
     */
    function configureDao(DaoRegistry dao, address tokenAddrToMint)
        external
        onlyAdapter(dao)
    {
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        bank.registerPotentialNewInternalToken(dao, tokenAddrToMint);
    }

    /**
     * @notice Creates and sponsors a tribute proposal to start the voting process.
     * @dev Applicant address must not be reserved.
     * @dev Only members of the DAO can sponsor a tribute proposal.
     * @param dao The DAO address.
     * @param proposalId The proposal id (managed by the client).
     * @param applicant The applicant address (who will receive the DAO internal tokens and become a member).
     * @param tokenToMint The address of the DAO internal token to be minted to the applicant.
     * @param requestAmount The amount requested of DAO internal tokens.
     * @param tokenAddr The address of the ERC-20 tokens that will be transferred to the DAO in exchange for DAO internal tokens.
     * @param tributeAmount The amount of tribute tokens.
     * @param tributeTokenOwner The owner of the ERC-20 tokens being provided as tribute.
     * @param data Additional information related to the tribute proposal.
     */
    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address applicant,
        address tokenToMint,
        uint256 requestAmount,
        address tokenAddr,
        uint256 tributeAmount,
        address tributeTokenOwner,
        bytes memory data
    ) external reimbursable(dao) {
        require(
            DaoHelper.isNotReservedAddress(applicant),
            "applicant is reserved address"
        );

        dao.submitProposal(proposalId);

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

        DaoHelper.potentialNewMember(applicant, dao, BankExtension(dao.getExtensionAddress(DaoHelper.BANK)));

        votingContract.startNewVotingForProposal(dao, proposalId, data);

        proposals[address(dao)][proposalId] = ProposalDetails(
            proposalId,
            applicant,
            tokenToMint,
            requestAmount,
            tokenAddr,
            tributeAmount,
            tributeTokenOwner
        );
    }

    /**
     * @notice 处理一个 tribute 提案，以处理 铸造和交换 DAO 内部代币以 换取贡品（通过投票）
     * @dev 提案 ID 必须存在
     * @dev 仅接受尚未处理的提案 
     * @dev 仅接受已完成投票的赞助提案 
     * @dev 作为贡品提供的 ERC-20 代币的所有者 必须 首先  “批准” 适配器作为这些代币的 spender（因此可以转移代币以获得通过的投票）
     * @dev ERC-20 代币必须在 DAO 银行注册 （如果需要， 通过的提案将检查并注册代币） 
     * @param dao DAO 地址
     * @param proposalId 提案 ID
     */
    function processProposal(DaoRegistry dao, bytes32 proposalId)
        external
        reimbursable(dao)
    {
        ProposalDetails memory proposal = proposals[address(dao)][proposalId];
        require(proposal.id == proposalId, "proposal does not exist");
        require(
            !dao.getProposalFlag(proposalId, DaoRegistry.ProposalFlag.PROCESSED),
            "proposal already processed"
        );

        IVoting votingContract = IVoting(dao.votingAdapter(proposalId));
        require(address(votingContract) != address(0), "adapter not found");

        IVoting.VotingState voteResult = votingContract.voteResult(
            dao,
            proposalId
        );

        dao.processProposal(proposalId);

        if (voteResult == IVoting.VotingState.PASS) {
            BankExtension bank = BankExtension(
                dao.getExtensionAddress(DaoHelper.BANK)
            );
            address tokenToMint = proposal.tokenToMint;
            address applicant = proposal.applicant;
            uint256 tributeAmount = proposal.tributeAmount;
            address tributeTokenOwner = proposal.tributeTokenOwner;
            require(
                bank.isInternalToken(tokenToMint),
                "it can only mint internal tokens"
            );

            if (!bank.isTokenAllowed(proposal.token)) {
                bank.registerPotentialNewToken(dao, proposal.token);
            }
            IERC20 erc20 = IERC20(proposal.token);
            erc20.safeTransferFrom(
                tributeTokenOwner,
                address(bank),
                tributeAmount
            );

            bank.addToBalance(
                dao,
                applicant,
                tokenToMint,
                proposal.requestAmount
            );
            bank.addToBalance(
                dao,
                DaoHelper.GUILD,
                proposal.token,
                tributeAmount
            );
        } else if (
            voteResult == IVoting.VotingState.NOT_PASS ||
            voteResult == IVoting.VotingState.TIE
        ) {
            //do nothing
        } else {
            revert("proposal has not been voted on yet");
        }
    }
}
