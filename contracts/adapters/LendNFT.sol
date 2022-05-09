pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../extensions/nft/NFT.sol";
import "../extensions/erc1155/ERC1155TokenExtension.sol";
import "../extensions/token/erc20/InternalTokenVestingExtension.sol";
import "../adapters/interfaces/IVoting.sol";
import "../helpers/DaoHelper.sol";
import "../guards/AdapterGuard.sol";
import "./modifiers/Reimbursable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract LendNFTContract is
    AdapterGuard,
    Reimbursable,
    IERC1155Receiver,
    IERC721Receiver
{
    struct ProcessProposal {
        DaoRegistry dao;
        bytes32 proposalId;
    }

    struct ProposalDetails {
        // 提案编号
        bytes32 id;
        // 申请人
        address applicant;
        // 申请者地址（将接收 DAO 内部代币并成为成员； 此地址可能与作为贡品的 ERC-721 代币的实际所有者不同 ）      
        address nftAddr;
        // nft 令牌标识符
        uint256 nftTokenId;
        // 捐赠数额
        uint256 tributeAmount;
        // DAO 内部代币（UNITS）的请求数量
        uint88 requestAmount;
        uint64 lendingPeriod;
        bool sentBack;
        uint64 lendingStart;
        address previousOwner;
    }

    // 跟踪每个 DAO 处理的所有 nft 致敬提案
    mapping(address => mapping(bytes32 => ProposalDetails)) public proposals;

    /**
     * @notice 为特定 DAO 配置 adapter， 向 DAO bank 注册 DAO 内部令牌
     * @dev 只有注册到 DAO 的适配器才能执行函数调用（或者如果 DAO 处于创建模式）
     * @dev 必须存在 DAO 银行扩展，并为此适配器配置适当的访问权限
     * @param dao DAO 地址
     * @param token 将被配置为内部令牌的令牌地址
     */
    function configureDao(DaoRegistry dao, address token)
        external
        onlyAdapter(dao)
    {
        // address ext = dao.getExtensionAddress(DaoHelper.BANK);
        // BankExtension bank = BankExtension(ext);

        // bank.registerPotentialNewInternalToken(dao, token);

        BankExtension(dao.getExtensionAddress(DaoHelper.BANK))
            .registerPotentialNewInternalToken(dao, token);
    }

    /**
     * @notice 创建并赞助一个 tribute 提案以启动投票过程  
     * @dev 申请人地址不得保留  
     * @dev 只有 DAO 的成员才能发起致敬提案  
     * @param dao DAO 地址  
     * @param proposalId 提案ID（由客户端管理）  
     * @param applicant 申请人地址（将收到 DAO 内部代币并成为会员）  
     * @param nftAddr 将转移到 DAO 以换取 DAO 内部代币的 ERC-721 代币的地址  
     * @param nftTokenId NFT 令牌 ID  
     * @param requestAmount DAO 内部代币（UNITS）的请求数量  
     * @param data 与致敬提案相关的附加信息 
     */

    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address applicant,
        address nftAddr,
        uint256 nftTokenId,
        uint88 requestAmount,
        uint64 lendingPeriod,
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
            nftAddr,
            nftTokenId,
            0,
            requestAmount,
            lendingPeriod,
            false,
            0,
            address(0x0)
        );
    }

    /**
    * @notice 处理提案以处理 DAO 内部代币的 铸造 和 交换 以获取贡品代币（通过投票） 
    * @dev 提案 ID 必须存在
    * @dev 仅接受 尚未处理的提案 
    * @dev 仅接受 已完成投票的赞助提案 
    * @dev 作为贡品提供的 ERC-721 代币的所有者必须首先单独 “批准” NFT 扩展作 为该代币的花费者 （以便 NFT 可以转移以获得通过的投票）     
    * @param dao The DAO address.
    * @param proposalId The proposal id.
    */
    // 该函数只能从 _onERC1155Received 和 _onERC721Received 函数中调用 , 可以防止重入攻击 
    function _processProposal(DaoRegistry dao, bytes32 proposalId)
        internal
        returns (
            ProposalDetails storage proposal,
            IVoting.VotingState voteResult
        )
    {
        proposal = proposals[address(dao)][proposalId];

        bool is_processed = dao.getProposalFlag(
            proposalId,
            DaoRegistry.ProposalFlag.PROCESSED
        );

        require(proposal.id == proposalId, "proposal does not exist");

        require(!is_processed, "proposal already processed");

        IVoting votingContract = IVoting(dao.votingAdapter(proposalId));
        require(address(votingContract) != address(0), "adapter not found");

        voteResult = votingContract.voteResult(dao, proposalId);

        dao.processProposal(proposalId);
        // if proposal passes and its an erc721 token - use NFT Extension
        // 如果提案通过并且它是一个 erc721 令牌 - 使用 NFT 扩展
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

            InternalTokenVestingExtension vesting = InternalTokenVestingExtension(
                    dao.getExtensionAddress(
                        DaoHelper.INTERNAL_TOKEN_VESTING_EXT
                    )
                );
            proposal.lendingStart = uint64(block.timestamp);
            //add vesting here
            vesting.createNewVesting(
                dao,
                proposal.applicant,
                DaoHelper.UNITS,
                proposal.requestAmount,
                proposal.lendingStart + proposal.lendingPeriod
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
     * @notice 将 NFT 发回给原始所有者.
     */
    function sendNFTBack(DaoRegistry dao, bytes32 proposalId)
        external
        reimbursable(dao)
    {
        ProposalDetails storage proposal = proposals[address(dao)][proposalId];

        require(proposal.lendingStart > 0, "lending not started");

        require(!proposal.sentBack, "already sent back");

        require(
            msg.sender == proposal.previousOwner,
            "only the previous owner can withdraw the NFT"
        );

        proposal.sentBack = true;

        // 开始了多长时间
        uint256 elapsedTime = block.timestamp - proposal.lendingStart;

        if (elapsedTime < proposal.lendingPeriod) {
            InternalTokenVestingExtension vesting = InternalTokenVestingExtension(
                    dao.getExtensionAddress(
                        DaoHelper.INTERNAL_TOKEN_VESTING_EXT
                    )
                );

            uint256 blockedAmount = vesting.getMinimumBalanceInternal(
                proposal.lendingStart,
                proposal.lendingStart + proposal.lendingPeriod,
                proposal.requestAmount
            );

            BankExtension(dao.getExtensionAddress(DaoHelper.BANK))
                .subtractFromBalance(
                    dao,
                    proposal.applicant,
                    DaoHelper.UNITS,
                    blockedAmount
                );
            vesting.removeVesting(
                dao,
                proposal.applicant,
                DaoHelper.UNITS,
                uint88(blockedAmount)
            );
        }

        // 只有 ERC-721 代币将包含贡品金额 == 0
        if (proposal.tributeAmount == 0) {
            NFTExtension nftExt = NFTExtension(
                dao.getExtensionAddress(DaoHelper.NFT)
            );

            nftExt.withdrawNFT(
                dao,
                proposal.previousOwner,
                proposal.nftAddr,
                proposal.nftTokenId
            );
        } else {
            ERC1155TokenExtension tokenExt = ERC1155TokenExtension(
                dao.getExtensionAddress(DaoHelper.ERC1155_EXT)
            );
            tokenExt.withdrawNFT(
                dao,
                DaoHelper.GUILD,
                proposal.previousOwner,
                proposal.nftAddr,
                proposal.nftTokenId,
                proposal.tributeAmount
            );
        }
    }

    /**
     *  @notice required function from IERC1155 standard to be able to to receive tokens， 接收令牌 1155
     */
    function onERC1155Received(
        address,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override returns (bytes4) {
        ProcessProposal memory ppS = abi.decode(data, (ProcessProposal));

        return _onERC1155Received(ppS.dao, ppS.proposalId, from, id, value);
    }

    function _onERC1155Received(
        DaoRegistry dao,
        bytes32 proposalId,
        address from,
        uint256 id,
        uint256 value
    ) internal reimbursable(dao) returns (bytes4) {
        (
            ProposalDetails storage proposal,
            IVoting.VotingState voteResult
        ) = _processProposal(dao, proposalId);

        require(proposal.nftTokenId == id, "wrong NFT");
        require(proposal.nftAddr == msg.sender, "wrong NFT addr");
        proposal.tributeAmount = value;
        proposal.previousOwner = from;

        // 严格匹配是为了确保投票通过 
        if (voteResult == IVoting.VotingState.PASS) {
            address erc1155ExtAddr = dao.getExtensionAddress(
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

        return this.onERC1155Received.selector;
    }

    /**
     *  @notice required function from IERC1155 standard to be able to to batch receive tokens， 批量接收令牌 1155
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

    // 批量接收 721
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        ProcessProposal memory ppS = abi.decode(data, (ProcessProposal));
        return _onERC721Received(ppS.dao, ppS.proposalId, from, tokenId);
    }

    function _onERC721Received(
        DaoRegistry dao,
        bytes32 proposalId,
        address from,
        uint256 tokenId
    ) internal reimbursable(dao) returns (bytes4) {
        (
            ProposalDetails storage proposal,
            IVoting.VotingState voteResult
        ) = _processProposal(dao, proposalId);
        require(proposal.nftTokenId == tokenId, "wrong NFT");
        require(proposal.nftAddr == msg.sender, "wrong NFT addr");
        proposal.tributeAmount = 0;
        proposal.previousOwner = from;
        IERC721 erc721 = IERC721(msg.sender);

        // Strict matching is expect to ensure the vote has passed
        if (voteResult == IVoting.VotingState.PASS) {
            NFTExtension nftExt = NFTExtension(
                dao.getExtensionAddress(DaoHelper.NFT)
            );
            erc721.approve(address(nftExt), proposal.nftTokenId);
            nftExt.collect(dao, proposal.nftAddr, proposal.nftTokenId);
        } else {
            erc721.safeTransferFrom(address(this), from, tokenId);
        }

        return this.onERC721Received.selector;
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
