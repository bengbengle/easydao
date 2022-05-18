pragma solidity ^0.8.0;



import "../core/DaoRegistry.sol";
import "../extensions/nft/NFT.sol";
import "../extensions/erc1155/ERC1155TokenExtension.sol";
import "../extensions/bank/Bank.sol";
import "../adapters/interfaces/IVoting.sol";
import "../guards/AdapterGuard.sol";
import "./modifiers/Reimbursable.sol";

import "../helpers/DaoHelper.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract TributeNFTContract is
    AdapterGuard,
    Reimbursable,
    IERC1155Receiver,
    IERC721Receiver
{
    using Address for address payable;

    struct ProcessProposal {
        DaoRegistry dao;
        bytes32 proposalId;
    }

    struct ProposalDetails {
        // The proposal id.
        bytes32 id;
        // 申请者地址（将接收 DAO 内部代币并 成为成员；此地址可能 与 作为贡品的 ERC-721 代币的 实际所有者 不同）
        address applicant;
        // ERC-721 代币的地址
        address nftAddr;
        // The nft token identifier.
        uint256 nftTokenId;
        // DAO 内部代币（UNITS）的请求数量。
        uint256 requestAmount;
    }

    // 跟踪每个 DAO 处理的所有 nft 致敬提案
    mapping(address => mapping(bytes32 => ProposalDetails)) public proposals;

    /**
      * @notice 为特定 DAO 配置适配器 
      * @notice 向 DAO 银行注册 DAO 内部代币 UNITS 
      * @dev 只有注册到 DAO 的适配器才能执行函数调用（或者如果 DAO 处于创建模式） 
      * @dev A DAO Bank 扩展必须 存在 并且 配置为对该适配器具有适当的访问权限
      * @param dao DAO 地址
      * @param tokenAddrToMint DAO 用于 铸造 的代币地址
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
      * @notice 创建并赞助一个 tribute 提案 以启动投票过程 
      * @dev 申请人地址不得是 保留地址 
      * @dev 只有 DAO 的成员才能 sponsor 致敬提案 
      * @param dao DAO 地址 
      * @param proposalId 提案ID（由客户端管理）

      * @param applicant 申请人地址（会收到 DAO 内部代币 并且 会成为会员） 
      * @param nftAddr 将转移到 DAO 以换取 DAO 内部代币的 ERC-721 或 ERC 1155 代币的地址
      * @param nftTokenId NFT 代币 ID
      
      * @param requestAmount DAO 内部代币的请求数量 
    
      * @param data 与致敬提案相关的附加信息
      */
    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address applicant,

        address nftAddr,
        uint256 nftTokenId,
        
        uint256 requestAmount,
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
        DaoHelper.potentialNewMember(
            applicant,
            dao, 
            BankExtension(dao.getExtensionAddress(DaoHelper.BANK))
        );

        dao.sponsorProposal(proposalId, sponsoredBy, address(votingContract));
        votingContract.startNewVotingForProposal(dao, proposalId, data);

        proposals[address(dao)][proposalId] = ProposalDetails(
            proposalId,
            applicant,
            nftAddr,
            nftTokenId,
            requestAmount
        );
    }

    /**
     * @notice IERC1155 标准所需的功能，以便能够接收令牌
     */
    function onERC1155Received(
        address,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override returns (bytes4) {
        ProcessProposal memory ppS = abi.decode(data, (ProcessProposal));
        
        ReimbursementData memory rData = ReimbursableLib.beforeExecution(ppS.dao);

        (
            ProposalDetails storage proposal,
            IVoting.VotingState voteResult
        ) = _processProposal(ppS.dao, ppS.proposalId);

        require(proposal.nftTokenId == id, "wrong NFT");
        require(proposal.nftAddr == msg.sender, "wrong NFT addr");

        if (voteResult == IVoting.VotingState.PASS) {
            address erc1155ExtAddr = ppS.dao.getExtensionAddress(
                DaoHelper.ERC1155_EXT
            );

            IERC1155 erc1155 = IERC1155(msg.sender);
            erc1155.safeTransferFrom(
                address(this),
                erc1155ExtAddr,
                id,
                value,
                ""
            );
        } else {
            IERC1155 erc1155 = IERC1155(msg.sender);
            erc1155.safeTransferFrom(address(this), from, id, value, "");
        }

        ReimbursableLib.afterExecution2(ppS.dao, rData, payable(from));
        return this.onERC1155Received.selector;
    }

    /**
     *  @notice 来自 IERC1155 标准的必需功能，以便能够批量接收令牌
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert("not supported");
    }

    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        ProcessProposal memory ppS = abi.decode(data, (ProcessProposal));

        ReimbursementData memory rData = ReimbursableLib.beforeExecution(ppS.dao);

        (
            ProposalDetails storage proposal,
            IVoting.VotingState voteResult
        ) = _processProposal(ppS.dao, ppS.proposalId);

        require(proposal.nftTokenId == tokenId, "wrong NFT");
        require(proposal.nftAddr == msg.sender, "wrong NFT addr");
        IERC721 erc721 = IERC721(msg.sender);

        // 如果提案通过并且它是一个 erc721 令牌 - 使用 NFT 扩展
        if (voteResult == IVoting.VotingState.PASS) {
            NFTExtension nftExt = NFTExtension(
                ppS.dao.getExtensionAddress(DaoHelper.NFT)
            );
            erc721.approve(address(nftExt), proposal.nftTokenId);

            nftExt.collect(ppS.dao, proposal.nftAddr, proposal.nftTokenId);
        } else {
            erc721.safeTransferFrom(address(this), from, tokenId);
        }

        ReimbursableLib.afterExecution2(ppS.dao, rData, payable(from));
        
        return this.onERC721Received.selector;
    }

    function _processProposal(DaoRegistry dao, bytes32 proposalId)
        internal
        returns (
            ProposalDetails storage proposal,
            IVoting.VotingState voteResult
        )
    {
        proposal = proposals[address(dao)][proposalId];
        require(proposal.id == proposalId, "proposal does not exist");
        require(
            !dao.getProposalFlag(
                proposalId,
                DaoRegistry.ProposalFlag.PROCESSED
            ),
            "proposal already processed"
        );

        IVoting votingContract = IVoting(dao.votingAdapter(proposalId));
        require(address(votingContract) != address(0), "adapter not found");

        voteResult = votingContract.voteResult(dao, proposalId);

        dao.processProposal(proposalId);
        //if proposal passes and its an erc721 token - use NFT Extension
        if (voteResult == IVoting.VotingState.PASS) {
            BankExtension bank = BankExtension(
                dao.getExtensionAddress(DaoHelper.BANK)
            );
            require(
                bank.isInternalToken(DaoHelper.UNITS),
                "UNITS token is not an internal token"
            );

            bank.addToBalance(
                dao,
                proposal.applicant,
                DaoHelper.UNITS,
                proposal.requestAmount
            );

            return (proposal, voteResult);
        } else if (
            voteResult == IVoting.VotingState.NOT_PASS ||
            voteResult == IVoting.VotingState.TIE
        ) {
            return (proposal, voteResult);
        } else {
            revert("proposal has not been voted on yet");
        }
    }
    
    /**
     * @notice Supports ERC-165 & ERC-1155 interfaces only.
     * @dev https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1155.md
     */
    function supportsInterface(bytes4 interfaceID)
        external
        pure
        override
        returns (bool)
    {
        return
            interfaceID == this.supportsInterface.selector ||
            interfaceID == this.onERC1155Received.selector ||
            interfaceID == this.onERC721Received.selector;
    }
}
