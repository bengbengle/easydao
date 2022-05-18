pragma solidity ^0.8.0;



import "../core/DaoRegistry.sol";
import "../guards/AdapterGuard.sol";
import "./modifiers/Reimbursable.sol";
import "./interfaces/IGuildKick.sol";
import "../helpers/GuildKickHelper.sol";
import "../adapters/interfaces/IVoting.sol";
import "../extensions/bank/Bank.sol";

contract GuildKickContract is IGuildKick, AdapterGuard, Reimbursable {
    // / 公会踢提案的状态 State of the guild kick proposal
    struct GuildKick {
        // 退出DAO的成员地址
        address memberToKick;
    }

    // 跟踪每个 DAO 执行过的 kick， dao -> proposalId -> kick
    mapping(address => mapping(bytes32 => GuildKick)) public kicks;

    /**
      * @notice 创建一个 Guild Kick 提案， 打开它进行投票，并赞助它 
      * @dev 成员不能踢自己。 
      * @dev 每个 DAO 一次只能执行一个 kick。 
      * @dev 只有拥有单位或战利品的成员才能被踢出。 
      * @dev 提案 ID 不能重复使用 
      * @param dao dao 地址
      * @param proposalId 公会踢提案 ID
      * @param memberToKick 应该被踢出 DAO 的成员地址 
      * @param data 与 kick 提案相关的附加信息
      */
    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address memberToKick,
        bytes calldata data
    ) external override reimbursable(dao) {
        IVoting votingContract = IVoting(
            dao.getAdapterAddress(DaoHelper.VOTING)
        );
        address submittedBy = votingContract.getSenderAddress(
            dao,
            address(this),
            data,
            msg.sender
        );

        // 检查 sender address 是否与要被踢的成员不同 以防止 自动踢
        require(submittedBy != memberToKick, "use ragequit");

        // 创建 guild kick 提案
        dao.submitProposal(proposalId);

        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        // 获取成员的 units 数量
        uint256 unitsToBurn = bank.balanceOf(memberToKick, DaoHelper.UNITS);

        // 获取成员的 loot 数量
        uint256 lootToBurn = bank.balanceOf(memberToKick, DaoHelper.LOOT);

        // 检查成员是否有足够的 units 转换为 loot
        require(unitsToBurn + lootToBurn > 0, "no units or loot");

        // 保存公会 kick 提案的状态
        kicks[address(dao)][proposalId] = GuildKick(memberToKick);

        GuildKickHelper.lockMemberTokens(
            dao,
            kicks[address(dao)][proposalId].memberToKick
        );

        // 赞助提案
        dao.sponsorProposal(proposalId, submittedBy, address(votingContract));
        // 开始投票
        votingContract.startNewVotingForProposal(dao, proposalId, data);
    }

    /**
     * @notice 处理 guild kick 提案 
     * @dev 只有活跃成员才能被踢出
     * @param dao dao 地址
     * @param proposalId 提案 ID
     */
    function processProposal(DaoRegistry dao, bytes32 proposalId)
        external
        override
        reimbursable(dao)
    {
        dao.processProposal(proposalId);

        // 检查提案是否通过
        IVoting votingContract = IVoting(dao.votingAdapter(proposalId));
        require(address(votingContract) != address(0), "adapter not found");
        IVoting.VotingState votingState = votingContract.voteResult(
            dao,
            proposalId
        );
        if (votingState == IVoting.VotingState.PASS) {
            GuildKickHelper.rageKick(
                dao,
                kicks[address(dao)][proposalId].memberToKick
            );
        } else if (
            votingState == IVoting.VotingState.NOT_PASS ||
            votingState == IVoting.VotingState.TIE
        ) {
            GuildKickHelper.unlockMemberTokens(
                dao,
                kicks[address(dao)][proposalId].memberToKick
            );
        } else {
            revert("voting is still in progress");
        }
    }
}
