pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../guards/AdapterGuard.sol";
import "./modifiers/Reimbursable.sol";
import "./interfaces/IGuildKick.sol";
import "../helpers/GuildKickHelper.sol";
import "../adapters/interfaces/IVoting.sol";
import "../helpers/FairShareHelper.sol";
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
     * @notice Creates a guild kick proposal, opens it for voting, and sponsors it.
     * @dev A member can not kick himself.
     * @dev Only one kick per DAO can be executed at time.
     * @dev Only members that have units or loot can be kicked out.
     * @dev Proposal ids can not be reused.
     * @param dao The dao address.
     * @param proposalId The guild kick proposal id.
     * @param memberToKick The member address that should be kicked out of the DAO.
     * @param data Additional information related to the kick proposal.
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
        // Checks if the sender address is not the same as the member to kick to prevent auto kick.
        // 检查 sender address 是否与要被踢的成员不同 以防止 自动踢
        require(submittedBy != memberToKick, "use ragequit");

        // 创建 guild kick 提案
        dao.submitProposal(proposalId);

        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        // Gets the number of units of the member
        uint256 unitsToBurn = bank.balanceOf(memberToKick, DaoHelper.UNITS);

        // Gets the number of loot of the member
        uint256 lootToBurn = bank.balanceOf(memberToKick, DaoHelper.LOOT);

        // 检查成员是否有足够的单位转换为战利品， 不可能溢出，因为每个 var 的最大值是 2^64
        // 参见 bank._createNewAmountCheckpoint 函数
        require(unitsToBurn + lootToBurn > 0, "no units or loot");

        // 保存公会 kick 提案的状态
        kicks[address(dao)][proposalId] = GuildKick(memberToKick);

        // 开始 guild kick 提案的投票过程
        votingContract.startNewVotingForProposal(dao, proposalId, data);

        GuildKickHelper.lockMemberTokens(
            dao,
            kicks[address(dao)][proposalId].memberToKick
        );

        // Sponsors the guild kick proposal.
        dao.sponsorProposal(proposalId, submittedBy, address(votingContract));
    }

    /**
     * @notice Process the guild kick proposal
     * @dev Only active members can be kicked out.
     * @param dao The dao address.
     * @param proposalId The guild kick proposal id.
     */
    function processProposal(DaoRegistry dao, bytes32 proposalId)
        external
        override
        reimbursable(dao)
    {
        dao.processProposal(proposalId);

        // Checks if the proposal has passed.
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
