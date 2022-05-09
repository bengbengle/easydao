pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/DaoRegistry.sol";
import "../../extensions/bank/Bank.sol";
import "../../guards/MemberGuard.sol";
import "../../guards/AdapterGuard.sol";
import "../modifiers/Reimbursable.sol";
import "../interfaces/IVoting.sol";
import "./Voting.sol";
import "./KickBadReporterAdapter.sol";
import "./OffchainVotingHash.sol";
import "./SnapshotProposalContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "../../helpers/DaoHelper.sol";
import "../../helpers/GuildKickHelper.sol";
import "../../helpers/OffchainVotingHelper.sol";

contract OffchainVotingContract is
    IVoting,
    MemberGuard,
    AdapterGuard,
    Ownable,
    Reimbursable
{
    struct ProposalChallenge {
        address reporter;
        uint256 units;
    }

    struct Voting {
        uint256 snapshot;
        address reporter;
        bytes32 resultRoot;
        uint256 nbYes;
        uint256 nbNo;
        uint64 startingTime;
        uint64 gracePeriodStartingTime;
        bool isChallenged;
        uint256 stepRequested;
        bool forceFailed;
        uint256 fallbackVotesCount;
        mapping(address => bool) fallbackVotes;
        uint256 nbMembers;
    }

    struct VotingDetails {
        uint256 snapshot;
        address reporter;
        bytes32 resultRoot;
        uint256 nbYes;
        uint256 nbNo;
        uint256 startingTime;
        uint256 gracePeriodStartingTime;
        bool isChallenged;
        uint256 stepRequested;
        bool forceFailed;
        uint256 fallbackVotesCount;
    }

    event VoteResultSubmitted(
        address daoAddress,
        bytes32 proposalId,
        uint256 nbNo,
        uint256 nbYes,
        bytes32 resultRoot,
        address memberAddr
    );
    event ResultChallenged(
        address daoAddress,
        bytes32 proposalId,
        bytes32 resultRoot
    );

    bytes32 public constant VotingPeriod =
        keccak256("offchainvoting.votingPeriod");
    bytes32 public constant GracePeriod =
        keccak256("offchainvoting.gracePeriod");
    bytes32 public constant FallbackThreshold =
        keccak256("offchainvoting.fallbackThreshold");

    SnapshotProposalContract private _snapshotContract;
    OffchainVotingHashContract public ovHash;
    OffchainVotingHelperContract private _ovHelper;
    KickBadReporterAdapter private _handleBadReporterAdapter;

    string private constant ADAPTER_NAME = "OffchainVotingContract";

    mapping(bytes32 => mapping(uint256 => uint256)) private retrievedStepsFlags;

    modifier onlyBadReporterAdapter() {
        require(msg.sender == address(_handleBadReporterAdapter), "only:hbra");
        _;
    }

    VotingContract private fallbackVoting;

    mapping(address => mapping(bytes32 => ProposalChallenge))
        private challengeProposals;
    mapping(address => mapping(bytes32 => Voting)) private votes;

    constructor(
        VotingContract _c,
        OffchainVotingHashContract _ovhc,
        OffchainVotingHelperContract _ovhelper,
        SnapshotProposalContract _spc,
        KickBadReporterAdapter _hbra,
        address _owner
    ) {
        require(address(_c) != address(0x0), "voting contract");
        require(
            address(_ovhc) != address(0x0),
            "offchain voting hash proposal"
        );
        require(address(_spc) != address(0x0), "snapshot proposal");
        require(address(_hbra) != address(0x0), "handle bad reporter");
        fallbackVoting = _c;
        ovHash = _ovhc;
        _handleBadReporterAdapter = _hbra;
        _snapshotContract = _spc;
        _ovHelper = _ovhelper;
        Ownable(_owner);
    }

    function configureDao(
        DaoRegistry dao,
        uint256 votingPeriod,
        uint256 gracePeriod,
        uint256 fallbackThreshold
    ) external onlyAdapter(dao) {
        dao.setConfiguration(VotingPeriod, votingPeriod);
        dao.setConfiguration(GracePeriod, gracePeriod);
        dao.setConfiguration(FallbackThreshold, fallbackThreshold);
    }

    function getVote(DaoRegistry dao, bytes32 proposalId)
        external
        view
        returns (VotingDetails memory)
    {
        Voting storage vote = votes[address(dao)][proposalId];

        return
            VotingDetails(
                vote.snapshot,
                vote.reporter,
                vote.resultRoot,
                vote.nbYes,
                vote.nbNo,
                vote.startingTime,
                vote.gracePeriodStartingTime,
                vote.isChallenged,
                vote.stepRequested,
                vote.forceFailed,
                vote.fallbackVotesCount
            );
    }

    function adminFailProposal(DaoRegistry dao, bytes32 proposalId)
        external
        onlyOwner
        reentrancyGuard(dao)
    {
        Voting storage vote = votes[address(dao)][proposalId];
        require(vote.startingTime > 0, "proposal has not started yet");

        vote.forceFailed = true;
    }

    function getAdapterName() external pure override returns (string memory) {
        return ADAPTER_NAME;
    }

    function getChallengeDetails(DaoRegistry dao, bytes32 proposalId)
        external
        view
        returns (uint256, address)
    {
        return (
            challengeProposals[address(dao)][proposalId].units,
            challengeProposals[address(dao)][proposalId].reporter
        );
    }

    function getSenderAddress(
        DaoRegistry dao,
        address actionId,
        bytes memory data,
        address addr
    ) external view override returns (address) {
        return
            _ovHelper.getSenderAddress(
                dao,
                actionId,
                data,
                addr,
                _snapshotContract
            );
    }

    /*
     * @notice 返回给定提案的投票结果
     * possible results:
     * 0: has not started
     * 1: tie
     * 2: pass
     * 3: not pass
     * 4: in progress
     */
    function voteResult(DaoRegistry dao, bytes32 proposalId)
        public
        view
        override
        returns (VotingState state)
    {
        Voting storage vote = votes[address(dao)][proposalId];
        if (_ovHelper.isFallbackVotingActivated(dao, vote.fallbackVotesCount)) {
            return fallbackVoting.voteResult(dao, proposalId);
        }

        return
            _ovHelper.getVoteResult(
                vote.startingTime,
                vote.forceFailed,
                vote.isChallenged,
                vote.stepRequested,
                vote.gracePeriodStartingTime,
                vote.nbYes,
                vote.nbNo,
                dao.getConfiguration(VotingPeriod),
                dao.getConfiguration(GracePeriod)
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
    ) external view returns (OffchainVotingHelperContract.BadNodeError) {
        return
            _ovHelper.getBadNodeError(
                dao,
                proposalId,
                submitNewVote,
                resultRoot,
                blockNumber,
                gracePeriodStartingTime,
                nbMembers,
                node
            );
    }

    /*
<<<<<<< Updated upstream
     *  如果 resultNode (vote) 有效，则将投票结果保存到存储中。
     * 一个有效的投票节点必须满足函数中的所有条件，所以它可以被存储。
     * 提交投票结果前需要检查的内容：
     * - 如果宽限期结束，什么也不做
     * - 如果是第一个结果（投票），现在是提交它的合适时间吗？
     * - nbYes 和 nbNo 之间的差异是 +50% 的选票吗？
     * - 这是在投票期之后吗？
     * - 如果我们已经有一个被挑战的结果，就像还没有结果一样
=======
     *  如果 resultNode (vote) 有效，则将投票结果保存到存储中  
     * 一个有效的投票节点必须满足函数中的所有条件，所以它可以被存储 
     * 提交投票结果前需要检查的内容： 
     * - 如果宽限期结束，什么也不做 
     * - 如果是第一个结果（投票），现在是提交它的合适时间吗？ 
     * - nbYes 和 nbNo 之间的差异是 +50% 的选票吗？ 
     * - 这是在投票期之后吗？ 
     * - 如果我们已经有一个被挑战的结果，就像还没有结果一样 
>>>>>>> Stashed changes
     * - 如果我们已经有一个未被质疑的结果， 新的比旧的重吗？
     */
    function submitVoteResult(
        DaoRegistry dao,
        bytes32 proposalId,
        bytes32 resultRoot,
        address reporter,
        OffchainVotingHashContract.VoteResultNode memory result,
        bytes memory rootSig
    ) external reimbursable(dao) {
        Voting storage vote = votes[address(dao)][proposalId];

        require(vote.snapshot > 0, "vote:not started");

        if (vote.resultRoot == bytes32(0) || vote.isChallenged) {
            require(
                _ovHelper.isReadyToSubmitResult(
                    dao,
                    vote.forceFailed,
                    vote.snapshot,
                    vote.startingTime,
                    dao.getConfiguration(VotingPeriod),
                    result.nbYes,
                    result.nbNo,
                    block.timestamp
                ),
                "vote:notReadyToSubmitResult"
            );
        }

        require(
            vote.gracePeriodStartingTime == 0 ||
                vote.gracePeriodStartingTime +
                    dao.getConfiguration(VotingPeriod) <=
                block.timestamp,
            "graceperiod finished!"
        );

        require(isActiveMember(dao, reporter), "not active member");

        uint256 membersCount = _ovHelper.checkMemberCount(
            dao,
            result.index,
            vote.snapshot
        );

        _ovHelper.checkBadNodeError(
            dao,
            proposalId,
            true,
            resultRoot,
            vote.snapshot,
            0,
            membersCount,
            result
        );

        (address adapterAddress, ) = dao.proposals(proposalId);

        bool isvalid = SignatureChecker.isValidSignatureNow(
            reporter,
            ovHash.hashResultRoot(dao, adapterAddress, resultRoot),
            rootSig
        );

        require(isvalid, "invalid sig");

        _verifyNode(dao, adapterAddress, result, resultRoot);

        require(
            vote.nbYes + vote.nbNo < result.nbYes + result.nbNo,
            "result weight too low"
        );

        // 检查新结果是否改变结果
        if (
            vote.gracePeriodStartingTime == 0 ||
            vote.nbNo > vote.nbYes != result.nbNo > result.nbYes
        ) {
            vote.gracePeriodStartingTime = uint64(block.timestamp);
        }

        vote.nbNo = result.nbNo;
        vote.nbYes = result.nbYes;
        vote.resultRoot = resultRoot;
        vote.reporter = dao.getAddressIfDelegated(reporter);
        vote.isChallenged = false;
        vote.nbMembers = membersCount;

        emit VoteResultSubmitted(
            address(dao),
            proposalId,
            result.nbNo,
            result.nbYes,
            resultRoot,
            vote.reporter
        );
    }

    function requestStep(
        DaoRegistry dao,
        bytes32 proposalId,
        uint256 index
    ) external reimbursable(dao) onlyMember(dao) {
        Voting storage vote = votes[address(dao)][proposalId];
        require(index < vote.nbMembers, "index out of bound");

        uint256 currentFlag = retrievedStepsFlags[vote.resultRoot][index / 256];

        require(
            DaoHelper.getFlag(currentFlag, index % 256) == false,
            "step already requested"
        );

        retrievedStepsFlags[vote.resultRoot][index / 256] = DaoHelper.setFlag(
            currentFlag,
            index % 256,
            true
        );

        require(vote.stepRequested == 0, "other step already requested");
        require(
            voteResult(dao, proposalId) == VotingState.GRACE_PERIOD,
            "should be grace period"
        );

        vote.stepRequested = index;
        vote.gracePeriodStartingTime = uint64(block.timestamp);
    }

    /*
     * @notice 如果 未出现 成员请求的步骤，此提案被标记为受到挑战
     * @notice 如果请求了，也过了宽限期，就挑战
     */

    function challengeMissingStep(DaoRegistry dao, bytes32 proposalId)
        external
        reimbursable(dao)
    {
        Voting storage vote = votes[address(dao)][proposalId];
        uint256 gracePeriod = dao.getConfiguration(GracePeriod);

        // 如果投票已经开始 但投票期还没有过去，它正在进行中
        require(vote.stepRequested > 0, "no step request");
        require(
            block.timestamp >= vote.gracePeriodStartingTime + gracePeriod,
            "grace period"
        );

        _challengeResult(dao, proposalId);
    }

    function provideStep(
        DaoRegistry dao,
        address adapterAddress,
        OffchainVotingHashContract.VoteResultNode memory node
    ) external reimbursable(dao) {
        Voting storage vote = votes[address(dao)][node.proposalId];

        require(vote.stepRequested == node.index, "wrong step provided");

        _verifyNode(dao, adapterAddress, node, vote.resultRoot);

        vote.stepRequested = 0;
        vote.gracePeriodStartingTime = uint64(block.timestamp);
    }

    function startNewVotingForProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        bytes memory data
    ) external override onlyAdapter(dao) {
        SnapshotProposalContract.ProposalMessage memory proposal = abi.decode(
            data,
            (SnapshotProposalContract.ProposalMessage)
        );
        (bool success, uint256 blockNumber) = ovHash.stringToUint(
            proposal.payload.snapshot
        );
        require(success, "snapshot conversion error");
        require(blockNumber <= block.number, "snapshot block in future");
        require(blockNumber > 0, "block number cannot be 0");

        votes[address(dao)][proposalId].startingTime = uint64(block.timestamp);
        votes[address(dao)][proposalId].snapshot = blockNumber;

        require(
            _getBank(dao).balanceOf(
                dao.getAddressIfDelegated(proposal.submitter),
                DaoHelper.UNITS
            ) > 0,
            "noActiveMember"
        );

        bool isvalid = SignatureChecker.isValidSignatureNow(
            proposal.submitter,
            _snapshotContract.hashMessage(dao, msg.sender, proposal),
            proposal.sig
        );

        require(isvalid, "invalid sig");
    }

    function challengeBadFirstNode(
        DaoRegistry dao,
        bytes32 proposalId,
        OffchainVotingHashContract.VoteResultNode memory node
    ) external reimbursable(dao) {
        require(node.index == 0, "only first node");

        Voting storage vote = votes[address(dao)][proposalId];
        require(vote.resultRoot != bytes32(0), "no result available yet!");
        (address actionId, ) = dao.proposals(proposalId);

        _verifyNode(dao, actionId, node, vote.resultRoot);

        if (
            ovHash.checkStep(
                dao,
                actionId,
                node,
                vote.snapshot,
                OffchainVotingHashContract.VoteStepParams(0, 0, proposalId)
            )
        ) {
            _challengeResult(dao, proposalId);
        } else {
            revert("nothing to challenge");
        }
    }

    function challengeBadNode(
        DaoRegistry dao,
        bytes32 proposalId,
        OffchainVotingHashContract.VoteResultNode memory node
    ) external reimbursable(dao) {
        Voting storage vote = votes[address(dao)][proposalId];
        if (
            _ovHelper.getBadNodeError(
                dao,
                proposalId,
                false,
                vote.resultRoot,
                vote.snapshot,
                vote.gracePeriodStartingTime,
                _getBank(dao).getPriorAmount(
                    DaoHelper.TOTAL,
                    DaoHelper.MEMBER_COUNT,
                    vote.snapshot
                ),
                node
            ) != OffchainVotingHelperContract.BadNodeError.OK
        ) {
            _challengeResult(dao, proposalId);
        } else {
            revert("nothing to challenge");
        }
    }

    function challengeBadStep(
        DaoRegistry dao,
        bytes32 proposalId,
        OffchainVotingHashContract.VoteResultNode memory nodePrevious,
        OffchainVotingHashContract.VoteResultNode memory nodeCurrent
    ) external reimbursable(dao) {
        Voting storage vote = votes[address(dao)][proposalId];
        bytes32 resultRoot = vote.resultRoot;

        (address actionId, ) = dao.proposals(proposalId);

        require(resultRoot != bytes32(0), "no result!");
        require(nodeCurrent.index == nodePrevious.index + 1, "not consecutive");

        _verifyNode(dao, actionId, nodeCurrent, vote.resultRoot);
        _verifyNode(dao, actionId, nodePrevious, vote.resultRoot);

        OffchainVotingHashContract.VoteStepParams
            memory params = OffchainVotingHashContract.VoteStepParams(
                nodePrevious.nbYes,
                nodePrevious.nbNo,
                proposalId
            );
        if (
            ovHash.checkStep(dao, actionId, nodeCurrent, vote.snapshot, params)
        ) {
            _challengeResult(dao, proposalId);
        } else {
            revert("nothing to challenge");
        }
    }

    function requestFallback(DaoRegistry dao, bytes32 proposalId)
        external
        reentrancyGuard(dao)
        onlyMember(dao)
    {
        VotingState state = voteResult(dao, proposalId);
        require(
            state != VotingState.PASS &&
                state != VotingState.NOT_PASS &&
                state != VotingState.TIE,
            "voting ended"
        );

        address memberAddr = dao.getAddressIfDelegated(msg.sender);
        // ,incorrect-equality
        require(
            votes[address(dao)][proposalId].fallbackVotes[memberAddr] == false,
            "fallback vote duplicate"
        );
        votes[address(dao)][proposalId].fallbackVotes[memberAddr] = true;
        votes[address(dao)][proposalId].fallbackVotesCount += 1;

        if (
            _ovHelper.isFallbackVotingActivated(
                dao,
                votes[address(dao)][proposalId].fallbackVotesCount
            )
        ) {
            fallbackVoting.startNewVotingForProposal(dao, proposalId, "");
        }
    }

    function sponsorChallengeProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address sponsoredBy
    ) external reentrancyGuard(dao) onlyBadReporterAdapter {
        dao.sponsorProposal(proposalId, sponsoredBy, address(this));
    }

    function processChallengeProposal(DaoRegistry dao, bytes32 proposalId)
        external
        reentrancyGuard(dao)
        onlyBadReporterAdapter
    {
        dao.processProposal(proposalId);
    }

    function _challengeResult(DaoRegistry dao, bytes32 proposalId) internal {
        votes[address(dao)][proposalId].isChallenged = true;
        address challengedReporter = votes[address(dao)][proposalId].reporter;
        bytes32 challengeProposalId = keccak256(
            abi.encodePacked(
                proposalId,
                votes[address(dao)][proposalId].resultRoot
            )
        );

        challengeProposals[address(dao)][
            challengeProposalId
        ] = ProposalChallenge(
            challengedReporter,
            _getBank(dao).balanceOf(challengedReporter, DaoHelper.UNITS)
        );

        GuildKickHelper.lockMemberTokens(dao, challengedReporter);

        dao.submitProposal(challengeProposalId);

        emit ResultChallenged(
            address(dao),
            proposalId,
            votes[address(dao)][proposalId].resultRoot
        );
    }

    function _verifyNode(
        DaoRegistry dao,
        address adapterAddress,
        OffchainVotingHashContract.VoteResultNode memory node,
        bytes32 root
    ) internal view {
        require(
            MerkleProof.verify(
                node.proof,
                root,
                ovHash.nodeHash(dao, adapterAddress, node)
            ),
            "proof:bad"
        );
    }

    function _getBank(DaoRegistry dao) internal view returns (BankExtension) {
        return BankExtension(dao.getExtensionAddress(DaoHelper.BANK));
    }
}
