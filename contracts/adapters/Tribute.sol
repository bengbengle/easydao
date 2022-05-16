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
      * @notice 为特定 DAO 配置适配器
      * @notice 向 DAO 银行注册 DAO 内部令牌
      * @dev 只有注册到 DAO 的适配器才能执行函数调用（或者如果 DAO 处于创建模式）
      * @dev A DAO Bank 扩展必须存在并且配置为对该适配器具有适当的访问权限
      * @param dao DAO 地址
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
      * @notice 创建并赞助一个致敬提案以启动投票过程 
      * @dev 申请人地址不得是 保留地址 
      * @dev 只有 DAO 的成员才能发起致敬提案 
      * @param dao DAO 地址 
      * @param proposalId 提案ID（由客户端管理）

      * @param applicant 申请人地址（将收到 DAO 内部代币并成为会员） 
      * @param tokenToMint 要铸造给申请人的 DAO 内部代币的地址 
      * @param requestAmount DAO 内部代币的请求数量 
      
      * @param tokenAddr 将转移到 DAO 以换取 DAO 内部代币的 ERC-20 代币的地址 
      * @param tributeAmount 贡品数量 
      * @param tributeTokenOwner 作为贡品提供的 ERC-20 代币的所有者 

      * @param data 与致敬提案相关的附加信息
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

        DaoHelper.potentialNewMember(
            applicant, 
            dao, 
            BankExtension(dao.getExtensionAddress(DaoHelper.BANK))
        );

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
