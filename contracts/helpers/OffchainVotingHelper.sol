pragma solidity ^0.8.0;



import "../core/DaoRegistry.sol";

import "../adapters/interfaces/IVoting.sol";

import "../adapters/voting/Voting.sol";

import "../adapters/voting/OffchainVotingHash.sol";

import "../adapters/voting/SnapshotProposalContract.sol";

import "./GovernanceHelper.sol";

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract OffchainVotingHelperContract {

    uint256 private constant NB_CHOICES = 2;
    
    // 投票期，宽限期，回退阈值
    bytes32 public constant VotingPeriod = keccak256("offchainvoting.votingPeriod"); 
    bytes32 public constant GracePeriod = keccak256("offchainvoting.gracePeriod"); 
    bytes32 public constant FallbackThreshold = keccak256("offchainvoting.fallbackThreshold"); 

    enum BadNodeError {
        OK,
        WRONG_PROPOSAL_ID,
        INVALID_CHOICE,
        AFTER_VOTING_PERIOD,
        BAD_SIGNATURE,
        INDEX_OUT_OF_BOUND,
        VOTE_NOT_ALLOWED
    }

    OffchainVotingHashContract private _ovHash;

    constructor(OffchainVotingHashContract _contract) {
        _ovHash = _contract;
    }

    // 检查成员数量 
    function checkMemberCount(
        DaoRegistry dao,
        uint256 resultIndex,
        uint256 blockNumber
    ) external view returns (uint256 membersCount) {
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );

        membersCount = bank.getPriorAmount(DaoHelper.TOTAL, DaoHelper.MEMBER_COUNT, blockNumber);

        require(membersCount - 1 == resultIndex, "index:member_count mismatch");
    }

    // 检查是否通过
    function checkBadNodeError(
        DaoRegistry dao,
        bytes32 proposalId,
        bool submitNewVote,
        bytes32 resultRoot,
        uint256 blockNumber,
        uint256 gracePeriodStartingTime,
        uint256 nbMembers,
        OffchainVotingHashContract.VoteResultNode memory node
    ) external view {
        require(
            getBadNodeError(
                dao,
                proposalId,
                submitNewVote,
                resultRoot,
                blockNumber,
                gracePeriodStartingTime,
                nbMembers,
                node
            ) == OffchainVotingHelperContract.BadNodeError.OK,
            "bad node"
        );
    }

    function getBadNodeError(
        DaoRegistry dao,
        bytes32 proposalId,
        bool submitNewVote,
        bytes32 resultRoot,
        uint256 blockNumber,
        uint256 gracePeriodStartingTime,
        uint256 nbMembers,
        OffchainVotingHashContract.VoteResultNode memory node
    ) public view returns (BadNodeError) {
        (address actionId, ) = dao.proposals(proposalId);

        require(resultRoot != bytes32(0), "no result available yet!");

        bytes32 hashCurrent = _ovHash.nodeHash(dao, actionId, node);
        require(
            MerkleProof.verify(node.proof, resultRoot, hashCurrent),
            "proof:bad"
        );

        if (node.index >= nbMembers) {
            return BadNodeError.INDEX_OUT_OF_BOUND;
        }

        address memberAddr = dao.getMemberAddress(node.index);

        // 无效的选择
        if (
            (node.sig.length == 0 && node.choice != 0) || // no vote
            (node.sig.length > 0 && !isValidChoice(node.choice))
        ) {
            return BadNodeError.INVALID_CHOICE;
        }

        //无效的提案哈希
        if (node.proposalId != proposalId) {
            return BadNodeError.WRONG_PROPOSAL_ID;
        }

        // 过了投票期
        if (!submitNewVote && node.timestamp > gracePeriodStartingTime) {
            return BadNodeError.AFTER_VOTING_PERIOD;
        }

        // 给定区块下，为多投票 地址
        address voter = dao.getPriorDelegateKey(memberAddr, blockNumber);

        bool hasVoted = _ovHash.hasVoted(
            dao,
            actionId,
            voter,
            node.timestamp,
            node.proposalId,
            node.choice,
            node.sig
        );

        if (node.sig.length > 0 && !hasVoted) {
            return BadNodeError.BAD_SIGNATURE;
        }

        // 如果权重 为 0，则该成员无权投票， 始终检查成员的权重，而不是代表的权重
        uint256 votingWeight = GovernanceHelper.getVotingWeight(dao, memberAddr, node.proposalId, blockNumber);

        if (node.choice != 0 && votingWeight == 0) {
            return BadNodeError.VOTE_NOT_ALLOWED;
        }

        return BadNodeError.OK;
    }

    function getSenderAddress(
        DaoRegistry dao,
        address actionId,
        bytes memory data,
        address,
        SnapshotProposalContract snapshotContract
    ) external view returns (address) {
        
        SnapshotProposalContract.ProposalMessage memory proposal = abi.decode(data, (SnapshotProposalContract.ProposalMessage));

        require(
            SignatureChecker.isValidSignatureNow(
                proposal.submitter,
                snapshotContract.hashMessage(dao, actionId, proposal),
                proposal.sig
            ),
            "invalid sig"
        );

        return proposal.submitter;
    }

    function isValidChoice(uint256 choice) public pure returns (bool) {
        return choice > 0 && choice < NB_CHOICES + 1;
    }

    function isFallbackVotingActivated(
        DaoRegistry dao,
        uint256 fallbackVotesCount
    ) external view returns (bool) {
        // 成员数量 * 
        uint256 count = dao.getNbMembers() * dao.getConfiguration(FallbackThreshold);

        return fallbackVotesCount > count / 100;
    }

    /**
     * @return 是否可以提交投票结果（nbYes - nbNo > 50 % total vote weight）
     * @param dao dao 地址
     * @param forceFailed 是否强制失败
     * @param snapshot 快照号
     * @param startingTime 投票开始时间
     * @param votingPeriod 投票期
     * @param nbYes 投 Yes 票数
     * @param nbNo 投 No 票数
     * @param blockTs 当前时间
     */
    function isReadyToSubmitResult(
        DaoRegistry dao,
        bool forceFailed,
        uint256 snapshot,
        uint256 startingTime,
        uint256 votingPeriod,
        uint256 nbYes,
        uint256 nbNo,
        uint256 blockTs
    ) external view returns (bool) {
        if (forceFailed) {
            return false;
        }

        uint256 diff;
        if (nbYes > nbNo) {
            diff = nbYes - nbNo;
        } else {
            diff = nbNo - nbYes;
        }

        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        uint256 totalWeight = bank.getPriorAmount(DaoHelper.TOTAL, DaoHelper.UNITS, snapshot);

        uint256 unvotedWeights = totalWeight - nbYes - nbNo;
        if (diff > unvotedWeights) {
            return true;
        }

        return startingTime + votingPeriod <= blockTs;
    }

    // 获取投票状态结果
    function getVoteResult(
        uint256 startingTime,
        bool forceFailed,
        bool isChallenged,
        uint256 stepRequested,
        uint256 gracePeriodStartingTime,
        uint256 nbYes,
        uint256 nbNo,
        uint256 votingPeriod, // dao.getConfiguration(VotingPeriod)
        uint256 gracePeriod //dao.getConfiguration(GracePeriod)
    ) external view returns (IVoting.VotingState state) {
        if (startingTime == 0) {
            return IVoting.VotingState.NOT_STARTED;
        }

        if (forceFailed) {
            return IVoting.VotingState.NOT_PASS;
        }

        if (isChallenged) {
            return IVoting.VotingState.IN_PROGRESS;
        }

        if (stepRequested > 0) {
            return IVoting.VotingState.IN_PROGRESS;
        }

        // proposal is in progress
        if (block.timestamp < startingTime + votingPeriod) {
            return IVoting.VotingState.IN_PROGRESS;
        }

        // proposal is GRACE_PERIOD
        if (
            gracePeriodStartingTime == 0 &&
            block.timestamp < startingTime + gracePeriod + votingPeriod
        ) {
            return IVoting.VotingState.GRACE_PERIOD;
        }

        // If the vote has started but the voting period has not passed yet, it's in progress
        // 如果投票已经开始， 但投票期尚未结束，则表示正在进行中
        if (block.timestamp < gracePeriodStartingTime + gracePeriod) {
            return IVoting.VotingState.GRACE_PERIOD;
        }

        if (nbYes > nbNo) {
            return IVoting.VotingState.PASS;
        }
        if (nbYes < nbNo) {
            return IVoting.VotingState.NOT_PASS;
        }

        return IVoting.VotingState.TIE;
    }
}
