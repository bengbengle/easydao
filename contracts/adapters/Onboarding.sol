pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "./interfaces/IOnboarding.sol";
import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "../adapters/interfaces/IVoting.sol";
import "../adapters/modifiers/Reimbursable.sol";
import "../guards/AdapterGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../helpers/DaoHelper.sol";


contract OnboardingContract is IOnboarding, AdapterGuard, Reimbursable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    bytes32 constant ChunkSize = keccak256("onboarding.chunkSize");
    bytes32 constant UnitsPerChunk = keccak256("onboarding.unitsPerChunk");
    bytes32 constant TokenAddr = keccak256("onboarding.tokenAddr");
    bytes32 constant MaximumChunks = keccak256("onboarding.maximumChunks");

    struct ProposalDetails {
        bytes32 id;
        address unitsToMint;
        uint160 amount;
        uint88 unitsRequested;
        address token;
        address payable applicant;
    }

    struct OnboardingDetails {
        uint88 chunkSize;
        uint88 numberOfChunks;
        uint88 unitsPerChunk;
        uint88 unitsRequested;
        uint96 totalUnits;
        uint160 amount;
    }

    // proposals per dao
    mapping(DaoRegistry => mapping(bytes32 => ProposalDetails)) public proposals;

    // minted units per dao, per token, per applicant
    mapping(DaoRegistry => mapping(address => mapping(address => uint88))) public units;

    /**
     * @notice 使用新配置更新 DAO 注册表 
     * @notice 使用新的潜在令牌更新银行扩展 
     * @param unitsToMint 如果提案通过，则需要铸造哪个代币 
     * @param chunkSize 每个购买的块需要铸造多少代币 
     * @param unitsPerChunk 每个块正在铸造多少个单位（来自 tokenAddr 的令牌） 
     * @param maximumChunks 最多可以购买多少块这有助于强制代币持有者去中心化 
     * @param tokenAddr 应以哪种货币 (tokenAddr) 进行入职
     */
    function configureDao(
        DaoRegistry dao,
        address unitsToMint,
        uint256 chunkSize,
        uint256 unitsPerChunk,
        uint256 maximumChunks,
        address tokenAddr
    ) external onlyAdapter(dao) {
        require(
            chunkSize > 0 && chunkSize < type(uint88).max,
            "chunkSize::invalid"
        );
        require(
            maximumChunks > 0 && maximumChunks < type(uint88).max,
            "maximumChunks::invalid"
        );
        require(
            unitsPerChunk > 0 && unitsPerChunk < type(uint88).max,
            "unitsPerChunk::invalid"
        );
        require(
            maximumChunks * unitsPerChunk < type(uint88).max,
            "potential overflow"
        );

        dao.setConfiguration(
            _configKey(unitsToMint, MaximumChunks),
            maximumChunks
        );
        dao.setConfiguration(_configKey(unitsToMint, ChunkSize), chunkSize);
        dao.setConfiguration(
            _configKey(unitsToMint, UnitsPerChunk),
            unitsPerChunk
        );
        dao.setAddressConfiguration(
            _configKey(unitsToMint, TokenAddr),
            tokenAddr
        );

        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        bank.registerPotentialNewInternalToken(dao, unitsToMint);
        bank.registerPotentialNewToken(dao, tokenAddr);
    }

    /**
     * @notice 提交并赞助提案只有成员才能调用此函数 
     * @param proposalId 提交给 DAO Registry 的提案 ID 
     * @param applicant 申请人地址 
     * @param tokenToMint 提案通过时要铸造的代币 
     * @param tokenAmount 要铸造的代币数量 
     * @param data 附加提案信息
     */
     
    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address payable applicant,
        address tokenToMint,
        uint256 tokenAmount,
        bytes memory data
    ) external override reimbursable(dao) {
        require(
            DaoHelper.isNotReservedAddress(applicant),
            "applicant is reserved address"
        );

        DaoHelper.potentialNewMember(
            applicant,
            dao,
            BankExtension(dao.getExtensionAddress(DaoHelper.BANK))
        );

        address tokenAddr = dao.getAddressConfiguration(
            _configKey(tokenToMint, TokenAddr)
        );

        _submitMembershipProposal(
            dao,
            proposalId,
            tokenToMint,
            applicant,
            tokenAmount,
            tokenAddr
        );

        _sponsorProposal(dao, proposalId, data);
    }

    /**
     *  一旦对提案的投票完成，就该处理它了任何人都可以调用这个函数 
     * @param proposalId 要处理的提案 ID它需要存在于 DAO 注册表中
     */
     
    function processProposal(DaoRegistry dao, bytes32 proposalId)
        external
        payable
        override
        reimbursable(dao)
    {
        ProposalDetails storage proposal = proposals[dao][proposalId];
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

        IVoting.VotingState voteResult = votingContract.voteResult(
            dao,
            proposalId
        );

        dao.processProposal(proposalId);

        if (voteResult == IVoting.VotingState.PASS) {
            address unitsToMint = proposal.unitsToMint;
            uint256 unitsRequested = proposal.unitsRequested;
            address applicant = proposal.applicant;
            BankExtension bank = BankExtension(
                dao.getExtensionAddress(DaoHelper.BANK)
            );
            require(
                bank.isInternalToken(unitsToMint),
                "it can only mint units"
            );

            bank.addToBalance(dao, applicant, unitsToMint, unitsRequested);

            if (proposal.token == DaoHelper.ETH_TOKEN) {
                // 此调用将 ETH 直接发送到 GUILD 银行，并且地址无法更改，因为它在 DaoHelper 中定义为常量
                 
                bank.addToBalance{value: proposal.amount}(
                    dao,
                    DaoHelper.GUILD,
                    proposal.token,
                    proposal.amount
                );
                if (msg.value > proposal.amount) {
                    payable(msg.sender).sendValue(msg.value - proposal.amount);
                }
            } else {
                bank.addToBalance(
                    dao,
                    DaoHelper.GUILD,
                    proposal.token,
                    proposal.amount
                );
                IERC20(proposal.token).safeTransferFrom(
                    msg.sender,
                    address(bank),
                    proposal.amount
                );
            }

            uint88 totalUnits = _getUnits(dao, unitsToMint, applicant) +
                proposal.unitsRequested;
            units[dao][unitsToMint][applicant] = totalUnits;
        } else if (
            voteResult == IVoting.VotingState.NOT_PASS ||
            voteResult == IVoting.VotingState.TIE
        ) {
            if (msg.value > 0) {
                payable(msg.sender).sendValue(msg.value);
            }
            //do nothing
        } else {
            revert("proposal has not been voted on yet");
        }
    }

    /**
     * @notice 开始对加入新成员的提案进行投票 
     * @param proposalId 要处理的提案 ID它需要存在于 DAO 注册表中
     */
    function _sponsorProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        bytes memory data
    ) internal {
        IVoting votingContract = IVoting(
            dao.getAdapterAddress(DaoHelper.VOTING)
        );
        address sponsoredBy = votingContract.getSenderAddress(
            dao,
            address(this),
            data,
            msg.sender
        );
        
        // 赞助，
        dao.sponsorProposal(proposalId, sponsoredBy, address(votingContract));
        
        // 开始投票了
        votingContract.startNewVotingForProposal(dao, proposalId, data);
    }

    /**
     * @notice Marks the proposalId as submitted in the DAO and saves the information in the internal adapter state.
     * @notice Updates the total of units issued in the DAO, and checks if it is within the limits.
     */
    function _submitMembershipProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address tokenToMint,
        address payable applicant,
        uint256 value,
        address token
    ) internal returns (uint160) {
        OnboardingDetails memory details = OnboardingDetails(0, 0, 0, 0, 0, 0);
        details.chunkSize = uint88(
            dao.getConfiguration(_configKey(tokenToMint, ChunkSize))
        );
        require(details.chunkSize > 0, "config chunkSize missing");

        details.numberOfChunks = uint88(value / details.chunkSize);
        require(details.numberOfChunks > 0, "not sufficient funds");

        details.unitsPerChunk = uint88(
            dao.getConfiguration(_configKey(tokenToMint, UnitsPerChunk))
        );

        require(details.unitsPerChunk > 0, "config unitsPerChunk missing");
        details.amount = details.numberOfChunks * details.chunkSize;
        details.unitsRequested = details.numberOfChunks * details.unitsPerChunk;
        details.totalUnits = _getUnits(dao, token, applicant) + details.unitsRequested;

        require(
            details.totalUnits / details.unitsPerChunk < dao.getConfiguration(_configKey(tokenToMint, MaximumChunks)),
            "total units for this member must be lower than the maximum"
        );

        proposals[dao][proposalId] = ProposalDetails(
            proposalId,
            tokenToMint,
            details.amount,
            details.unitsRequested,
            token,
            applicant
        );

        dao.submitProposal(proposalId);

        return details.amount;
    }

    /**
     * @notice 获取当前的单位数
     * @param dao 包含单元的 DAO 
     * @param token 铸造单位的代币地址 
     * @param applicant 持有单位的申请人地址
     */
    function _getUnits(
        DaoRegistry dao,
        address token,
        address applicant
    ) internal view returns (uint88) {
        return units[dao][token][applicant];
    }

    /**
     * @notice 通过使用字符串键对 地址进行编码来构建 配置键 
     * @param tokenAddrToMint 要编码的地址
     * @param key 要编码的密钥
     */
    function _configKey(address tokenAddrToMint, bytes32 key)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(tokenAddrToMint, key));
    }
}
