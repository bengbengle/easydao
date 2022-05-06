pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/DaoRegistry.sol";
import "../../extensions/bank/Bank.sol";
import "../../extensions/token/erc20/ERC20TokenExtension.sol";
import "../../utils/Signatures.sol";
import "../interfaces/IVoting.sol";
import "./Voting.sol";
import "./KickBadReporterAdapter.sol";
import "./SnapshotProposalContract.sol";
import "../../helpers/DaoHelper.sol";
import "../../helpers/GovernanceHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";


contract OffchainVotingHashContract {
    string public constant VOTE_RESULT_NODE_TYPE = "Message(uint64 timestamp,uint88 nbYes,uint88 nbNo,uint32 index,uint32 choice,bytes32 proposalId)";
    string public constant VOTE_RESULT_ROOT_TYPE = "Message(bytes32 root)";
    bytes32 public constant VOTE_RESULT_NODE_TYPEHASH = keccak256(abi.encodePacked(VOTE_RESULT_NODE_TYPE));
    bytes32 public constant VOTE_RESULT_ROOT_TYPEHASH = keccak256(abi.encodePacked(VOTE_RESULT_ROOT_TYPE));

    bytes32 constant VotingPeriod = keccak256("offchainvoting.votingPeriod");
    bytes32 constant GracePeriod = keccak256("offchainvoting.gracePeriod");
    bytes32 constant FallbackThreshold = keccak256("offchainvoting.fallbackThreshold");

    mapping(address => mapping(bytes32 => mapping(uint256 => uint256))) flags;

    SnapshotProposalContract public snapshotContract;

    struct VoteStepParams {
        uint256 previousYes;
        uint256 previousNo;
        bytes32 proposalId;
    }

    struct VoteResultNode {
        uint32 choice;
        uint64 index;
        uint64 timestamp;
        uint88 nbNo;
        uint88 nbYes;
        bytes sig;
        bytes32 proposalId;
        bytes32[] proof;
    }

    constructor(SnapshotProposalContract _spc) {
        require(address(_spc) != address(0x0), "snapshot proposal");
        snapshotContract = _spc;
    }

    function hashResultRoot(
        DaoRegistry dao,
        address actionId,
        bytes32 resultRoot
    ) external view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    snapshotContract.DOMAIN_SEPARATOR(dao, actionId),
                    keccak256(abi.encode(VOTE_RESULT_ROOT_TYPEHASH, resultRoot))
                )
            );
    }

    function hashVotingResultNode(VoteResultNode memory node)
        public
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    VOTE_RESULT_NODE_TYPEHASH,
                    node.timestamp,
                    node.nbYes,
                    node.nbNo,
                    node.index,
                    node.choice,
                    node.proposalId
                )
            );
    }

    function nodeHash(
        DaoRegistry dao,
        address actionId,
        VoteResultNode memory node
    ) external view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    snapshotContract.DOMAIN_SEPARATOR(dao, actionId),
                    hashVotingResultNode(node)
                )
            );
    }

    function hasVoted(
        DaoRegistry dao,
        address actionId,
        address voter,
        uint64 timestamp,
        bytes32 proposalId,
        uint32 choiceIdx,
        bytes memory sig
    ) public view returns (bool) {

        SnapshotProposalContract.VotePayload  votePayload = SnapshotProposalContract.VotePayload(choiceIdx, proposalId);

        SnapshotProposalContract.VoteMessage voteMessage =  SnapshotProposalContract.VoteMessage(timestamp, votePayload);

        bytes32 voteHash = snapshotContract.hashVote(dao, actionId, voteMessage);

        return SignatureChecker.isValidSignatureNow(voter, voteHash, sig);
    }

    function stringToUint(string memory s)
        external
        pure
        returns (bool success, uint256 result)
    {
        bytes memory b = bytes(s);
        result = 0;
        success = false;
        for (uint256 i = 0; i < b.length; i++) {
            if (uint8(b[i]) >= 48 && uint8(b[i]) <= 57) {
                result = result * 10 + (uint8(b[i]) - 48);
                success = true;
            } else {
                result = 0;
                success = false;
                break;
            }
        }
        return (success, result);
    }

    function checkStep(
        DaoRegistry dao,
        address actionId,
        OffchainVotingHashContract.VoteResultNode memory node,
        uint256 snapshot,
        VoteStepParams memory params
    ) external view returns (bool) {
        address voter = dao.getPriorDelegateKey(
            dao.getMemberAddress(node.index),
            snapshot
        );
        uint256 weight = GovernanceHelper.getVotingWeight(
            dao,
            voter,
            node.proposalId,
            snapshot
        );

        if (node.choice == 0) {
            if (params.previousYes != node.nbYes) {
                return true;
            } else if (params.previousNo != node.nbNo) {
                return true;
            }
        }

        if (
            hasVoted(
                dao,
                actionId,
                voter,
                node.timestamp,
                node.proposalId,
                1,
                node.sig
            )
        ) {
            if (params.previousYes + weight != node.nbYes) {
                return true;
            } else if (params.previousNo != node.nbNo) {
                return true;
            }
        }
        if (
            hasVoted(
                dao,
                actionId,
                voter,
                node.timestamp,
                node.proposalId,
                2,
                node.sig
            )
        ) {
            if (params.previousYes != node.nbYes) {
                return true;
            } else if (params.previousNo + weight != node.nbNo) {
                return true;
            }
        }

        return false;
    }
}
