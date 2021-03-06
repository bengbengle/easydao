// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../core/DaoRegistry.sol";
import "../../guards/MemberGuard.sol";
import "../interfaces/IVoting.sol";
import "./OffchainVoting.sol";

import "../../helpers/GuildKickHelper.sol";

contract KickBadReporterAdapter is MemberGuard {
    
    function sponsorProposal(DaoRegistry dao, bytes32 proposalId, bytes calldata data) 
        external 
    {
        OffchainVotingContract votingContract = _getVotingContract(dao);
        address sponsoredBy = votingContract.getSenderAddress(dao, address(this), data, msg.sender);

        votingContract.sponsorChallengeProposal(dao, proposalId, sponsoredBy);
        votingContract.startNewVotingForProposal(dao, proposalId, data);
    }

    function processProposal(DaoRegistry dao, bytes32 proposalId) external {
        OffchainVotingContract votingContract = _getVotingContract(dao);
        votingContract.processChallengeProposal(dao, proposalId);

        IVoting.VotingState votingState = votingContract.voteResult(dao, proposalId);

        // the person has been kicked out
        if (votingState == IVoting.VotingState.PASS) {
            (, address challengeAddress) = votingContract.getChallengeDetails(
                dao,
                proposalId
            );
            GuildKickHelper.rageKick(dao, challengeAddress);
        } else if (
            votingState == IVoting.VotingState.NOT_PASS ||
            votingState == IVoting.VotingState.TIE
        ) {
            (, address challengeAddress) = votingContract.getChallengeDetails(
                dao,
                proposalId
            );
            GuildKickHelper.unlockMemberTokens(dao, challengeAddress);
        } else {
            revert("vote not finished yet");
        }
    }

    function _getVotingContract(DaoRegistry dao)
        internal
        view
        returns (OffchainVotingContract)
    {
        address addr = dao.getAdapterAddress(DaoHelper.VOTING);
        return OffchainVotingContract(payable(addr));
    }
}
