// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../core/DaoRegistry.sol";
import "../../extensions/bank/Bank.sol";
import "../../guards/MemberGuard.sol";
import "../../guards/AdapterGuard.sol";
import "../interfaces/IVoting.sol";
import "../../helpers/DaoHelper.sol";
import "../modifiers/Reimbursable.sol";
import "../../helpers/GovernanceHelper.sol";

contract VotingContract is IVoting, MemberGuard, AdapterGuard, Reimbursable {
    struct Voting {
        uint256 nbYes;
        uint256 nbNo;
        uint256 startingTime;
        uint256 blockNumber;
        mapping(address => uint256) votes;
    }

    bytes32 constant VotingPeriod = keccak256("voting.votingPeriod");
    bytes32 constant GracePeriod = keccak256("voting.gracePeriod");

    mapping(address => mapping(bytes32 => Voting)) public votes;

    string public constant ADAPTER_NAME = "VotingContract";

    /**
     * @notice 返回适配器名称 ， 有助于识别 在 DAO 中 配置的投票适配器
     */
    function getAdapterName() 
        external 
        pure 
        override 
        returns (string memory) 
    {
        return ADAPTER_NAME;
    }

    /**
    * @notice 为 DAO 配置 投票期 和 宽限期
    * @param votingPeriod 以秒为单位的 投票周期 
    * @param gracePeriod 以秒为单位的 宽限期
     */
    function configureDao(
        DaoRegistry dao,
        uint256 votingPeriod,
        uint256 gracePeriod
    ) external onlyAdapter(dao) {
        dao.setConfiguration(VotingPeriod, votingPeriod);
        dao.setConfiguration(GracePeriod, gracePeriod);
    }

    /**
     * @notice 统计一个新的投票提案，考虑区块时间和数量
     * @notice 从适配器调用此函数来计算提案的投票开始时间
     * @param proposalId 正在启动的提案 ID
     */
    function startNewVotingForProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        bytes calldata
    ) external override onlyAdapter(dao) {
        Voting storage vote = votes[address(dao)][proposalId];
        vote.startingTime = block.timestamp;
        vote.blockNumber = block.number;
    }

    /**
     * @notice 发件人地址， 这个函数是 IVoting 需要的，通常链下投票有不同的规则来识别发送者，但这里不是这样，所以我们只返回 fallback 参数：发送者  
     * @param sender 在没有找到其他人的情况下应该返回的后备发件人地址 
     */
    function getSenderAddress(
        DaoRegistry,
        address,
        bytes memory,
        address sender
    ) external pure override returns (address) {
        return sender;
    }

    /**
     * @notice 向 DAO Registry 提交投票， 投票必须在 startNewVotingForProposal 中定义的开始时间之后提交  
     * @notice 投票需要在投票期内提交， 会员不能投票两次或多次  
     * @param dao DAO 地址  
     * @param proposalId 该提案需要被赞助，而不是被处理  
     * @param voteValue 只允许是 (1) 和否 (2) 投票 
     */
    function submitVote(
        DaoRegistry dao,
        bytes32 proposalId,
        uint256 voteValue
    ) external onlyMember(dao) reimbursable(dao) {
        require(
            dao.getProposalFlag(proposalId, DaoRegistry.ProposalFlag.SPONSORED),
            "the proposal has not been sponsored yet"
        );

        require(
            !dao.getProposalFlag(
                proposalId,
                DaoRegistry.ProposalFlag.PROCESSED
            ),
            "the proposal has already been processed"
        );

        require(
            voteValue < 3 && voteValue > 0,
            "only yes (1) and no (2) are possible values"
        );

        Voting storage vote = votes[address(dao)][proposalId];
        require(
            vote.startingTime > 0,
            "this proposalId has no vote going on at the moment"
        );
        require(
            block.timestamp < vote.startingTime + dao.getConfiguration(VotingPeriod),
            "vote has already ended"
        );

        address memberAddr = DaoHelper.msgSender(dao, msg.sender);

        require(vote.votes[memberAddr] == 0, "member has already voted");

        uint256 votingWeight = GovernanceHelper.getVotingWeight(dao, memberAddr, proposalId, vote.blockNumber);

        if (votingWeight == 0) revert("vote not allowed");

        vote.votes[memberAddr] = voteValue;

        if (voteValue == 1) {
            vote.nbYes = vote.nbYes + votingWeight;
        } else if (voteValue == 2) {
            vote.nbNo = vote.nbNo + votingWeight;
        }
    }

    /**
     * @notice 根据提案计算投票结果  
     * @param dao DAO 地址  
     * @param proposalId 需要计算投票的提案  
     * @return state 状态
     * The possible results are:
     * 0: has not started
     * 1: tie 平局
     * 2: pass 通过
     * 3: not pass 未通过
     * 4: in progress 处理中
     */
    function voteResult(DaoRegistry dao, bytes32 proposalId)
        external
        view
        override
        returns (VotingState state)
    {
        Voting storage vote = votes[address(dao)][proposalId];
        
        // 未开始
        if (vote.startingTime == 0) {
            return VotingState.NOT_STARTED;
        }
        // 投票中
        if (
            block.timestamp < vote.startingTime + dao.getConfiguration(VotingPeriod)
        ) {
            return VotingState.IN_PROGRESS;
        }
        // 宽限期
        if (
            block.timestamp < vote.startingTime + dao.getConfiguration(VotingPeriod) + dao.getConfiguration(GracePeriod)
        ) {
            return VotingState.GRACE_PERIOD;
        }
        // 投票结束，已出结果， 1：平局，2：通过，3：未通过
        if (vote.nbYes > vote.nbNo) {
            return VotingState.PASS;
        } else if (vote.nbYes < vote.nbNo) {
            return VotingState.NOT_PASS;
        } else {
            return VotingState.TIE;
        }
    }
}
