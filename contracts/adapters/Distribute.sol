pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../guards/AdapterGuard.sol";
import "./modifiers/Reimbursable.sol";
import "../adapters/interfaces/IVoting.sol";
import "../adapters/interfaces/IDistribute.sol";
import "../helpers/FairShareHelper.sol";
import "../helpers/DaoHelper.sol";
import "../extensions/bank/Bank.sol";

/**
MIT License

Copyright (c) 2020 Openlaw

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */

contract DistributeContract is IDistribute, AdapterGuard, Reimbursable {
    // Event to indicate the distribution process has been completed
    // if the unitHolder address is 0x0, then the amount were distributed to all members of the DAO.
    // 表示分发过程已经完成的事件 
    // 如果 unitHolder 地址为 0x0，则金额分配给 DAO 的所有成员。
    event Distributed(
        address daoAddress,
        address token,
        uint256 amount,
        address unitHolder
    );

    // The distribution status
    // 分发 状态
    enum DistributionStatus {
        NOT_STARTED,
        IN_PROGRESS,
        DONE,
        FAILED
    }

    // State of the distribution proposal
    // 分配提案的状态
    struct Distribution {
        // The distribution token in which the members should receive the funds. Must be supported by the DAO.
        // 代币地址，成员应收到资金的分配代币。必须得到 DAO 的支持。
        address token;
        // The amount to distribute.
        // 金额
        uint256 amount;
        // The unit holder address that will receive the funds. If 0x0, the funds will be distributed to all members of the DAO.
        // 将接收资金的单位持有人地址。如果为 0x0，资金将分配给 DAO 的所有成员
        address unitHolderAddr;
        // The distribution status.
        DistributionStatus status;
        // Current iteration index to control the cached for-loop.
        // 当前迭代索引来控制缓存的for循环
        uint256 currentIndex;
        // The block number in which the proposal has been created.
        // 创建提案的区块号
        uint256 blockNumber;
    }

    // Keeps track of all the distributions executed per DAO.
    // 跟踪每个 DAO 执行的所有分发
    mapping(address => mapping(bytes32 => Distribution)) public distributions;

    // Keeps track of the latest ongoing distribution proposal per DAO to ensure only 1 proposal can be processed at a time.
    // 跟踪每个 DAO 的最新正在进行的分发提案，以确保一次只能处理 1 个提案。
    mapping(address => bytes32) public ongoingDistributions;

    /**
     * @notice Creates a distribution proposal for one or all members of the DAO, opens it for voting, and sponsors it.
     * @dev Only tokens that are allowed by the Bank are accepted.
     * @dev If the unitHolderAddr is 0x0, then the funds will be distributed to all members of the DAO.
     * @dev Proposal ids can not be reused.
     * @dev The amount must be greater than zero.
     * @param dao The dao address.
     * @param proposalId The distribution proposal id.
     * @param unitHolderAddr The member address that should receive the funds, if 0x0, the funds will be distributed to all members of the DAO.
     * @param token The distribution token in which the members should receive the funds. Must be supported by the DAO.
     * @param amount The amount to distribute.
     * @param data Additional information related to the distribution proposal.
     * @param token 成员应收到资金的分配代币。必须得到 DAO 的支持
     *
     */
     
        function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address unitHolderAddr,
        address token,
        uint256 amount,
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

        require(amount > 0, "invalid amount");

        // Creates the distribution proposal.
        dao.submitProposal(proposalId);

        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        require(bank.isTokenAllowed(token), "token not allowed");

        // Only check the number of units if there is a valid unit holder address.
        if (unitHolderAddr != address(0x0)) {
            // Gets the number of units of the member
            uint256 units = bank.balanceOf(unitHolderAddr, DaoHelper.UNITS);
            // Checks if the member has enough units to reveice the funds.
            require(units > 0, "not enough units");
        }

        // Saves the state of the proposal.
        distributions[address(dao)][proposalId] = Distribution(
            token,
            amount,
            unitHolderAddr,
            DistributionStatus.NOT_STARTED,
            0,
            block.number
        );

        // Starts the voting process for the proposal.
        votingContract.startNewVotingForProposal(dao, proposalId, data);

        // Sponsors the proposal.
        dao.sponsorProposal(proposalId, submittedBy, address(votingContract));
    }

    /**
     * @notice Process the distribution proposal, calculates the fair amount of funds to distribute to the members based on the units holdings.
     * @dev A distribution proposal proposal must be in progress.
     * @dev Only one proposal per DAO can be executed at time.
     * @dev Only active members can receive funds.
     * @dev Only proposals that passed the voting can be set to In Progress status.
     * @param dao The dao address.
     * @param proposalId The distribution proposal id.
     * @notice 处理分配方案，根据单位持有量计算分配给会员的公平金额。 
     * @dev 分发提案提案必须正在进行中。 
     * @dev 每个 DAO 一次只能执行一个提案。 
     * @dev 只有活跃会员才能收到资金。 
     * @dev 只有通过投票的提案才能设置为进行中状态。 
     * @param dao dao 地址。 
     * @param proposalId 分发提案 ID。
     */
    // The function is protected against reentrancy with the reentrancyGuard
    // Which prevents concurrent modifications in the DAO registry.
    // 使用 reentrancyGuard 防止函数重入，这可以防止 DAO 注册表中的并发修改。
     
    function processProposal(DaoRegistry dao, bytes32 proposalId)
        external
        override
        reimbursable(dao)
    {
        dao.processProposal(proposalId);

        // Checks if the proposal exists or is not in progress yet.
        // 检查提案是否存在或尚未进行中
        Distribution storage distribution = distributions[address(dao)][
            proposalId
        ];
        require(
            distribution.status == DistributionStatus.NOT_STARTED,
            "proposal already completed or in progress"
        );

        // Checks if there is an ongoing proposal, only one proposal can be executed at time.
        bytes32 ongoingProposalId = ongoingDistributions[address(dao)];
        require(
            ongoingProposalId == bytes32(0) ||
                distributions[address(dao)][ongoingProposalId].status !=
                DistributionStatus.IN_PROGRESS,
            "another proposal already in progress"
        );

        // Checks if the proposal has passed.
        IVoting votingContract = IVoting(dao.votingAdapter(proposalId));
        require(address(votingContract) != address(0), "adapter not found");

        IVoting.VotingState voteResult = votingContract.voteResult(
            dao,
            proposalId
        );
        if (voteResult == IVoting.VotingState.PASS) {
            distribution.status = DistributionStatus.IN_PROGRESS;
            distribution.blockNumber = block.number;
            ongoingDistributions[address(dao)] = proposalId;

            BankExtension bank = BankExtension(
                dao.getExtensionAddress(DaoHelper.BANK)
            );

            bank.internalTransfer(
                dao,
                DaoHelper.GUILD,
                DaoHelper.ESCROW,
                distribution.token,
                distribution.amount
            );
        } else if (
            voteResult == IVoting.VotingState.NOT_PASS ||
            voteResult == IVoting.VotingState.TIE
        ) {
            distribution.status = DistributionStatus.FAILED;
        } else {
            revert("proposal has not been voted on");
        }
    }

    /**
     * @notice Transfers the funds from the Guild account to the member's internal accounts.
     * @notice The amount of funds is caculated using the historical number of units of each member.
     * @dev A distribution proposal must be in progress.
     * @dev Only proposals that have passed the voting can be completed.
     * @dev Only active members can receive funds.
     * @param dao The dao address.
     * @param toIndex The index to control the cached for-loop.
     */
     
        function distribute(DaoRegistry dao, uint256 toIndex)
        external
        override
        reimbursable(dao)
    {
        // Checks if the proposal does not exist or is not completed yet
        bytes32 ongoingProposalId = ongoingDistributions[address(dao)];
        Distribution storage distribution = distributions[address(dao)][
            ongoingProposalId
        ];
        uint256 blockNumber = distribution.blockNumber;
        require(
            distribution.status == DistributionStatus.IN_PROGRESS,
            "distrib completed or not exist"
        );

        // Check if the given index was already processed
        uint256 currentIndex = distribution.currentIndex;
        require(currentIndex <= toIndex, "toIndex too low");

        address token = distribution.token;
        uint256 amount = distribution.amount;

        // Get the total number of units when the proposal was processed.
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );

        address unitHolderAddr = distribution.unitHolderAddr;
        if (unitHolderAddr != address(0x0)) {
            distribution.status = DistributionStatus.DONE;
            _distributeOne(
                dao,
                bank,
                unitHolderAddr,
                blockNumber,
                token,
                amount
            );
             
            emit Distributed(address(dao), token, amount, unitHolderAddr);
        } else {
            // Set the max index supported which is based on the number of members
            uint256 nbMembers = dao.getNbMembers();
            uint256 maxIndex = toIndex;
            if (maxIndex > nbMembers) {
                maxIndex = nbMembers;
            }

            distribution.currentIndex = maxIndex;
            if (maxIndex == nbMembers) {
                distribution.status = DistributionStatus.DONE;
                 
                emit Distributed(address(dao), token, amount, unitHolderAddr);
            }

            _distributeAll(
                dao,
                bank,
                currentIndex,
                maxIndex,
                blockNumber,
                token,
                amount
            );
        }
    }

    /**
     * @notice Updates the holder account with the amount based on the token parameter.
     * @notice It is an internal transfer only that happens in the Bank extension.
     */
    function _distributeOne(
        DaoRegistry dao,
        BankExtension bank,
        address unitHolderAddr,
        uint256 blockNumber,
        address token,
        uint256 amount
    ) internal {
        uint256 memberTokens = DaoHelper.priorMemberTokens(
            bank,
            unitHolderAddr,
            blockNumber
        );
        require(memberTokens > 0, "not enough tokens");
        // Distributes the funds to 1 unit holder only
        bank.internalTransfer(
            dao,
            DaoHelper.ESCROW,
            unitHolderAddr,
            token,
            amount
        );
    }

    /**
     * @notice Updates all the holder accounts with the amount based on the token parameter.
     * @notice It is an internal transfer only that happens in the Bank extension.
     * @notice 使用基于 token 参数的金额更新所有持有人账户。 
     * @notice 这是仅在银行分机中发生的内部转账。
     */
    function _distributeAll(
        DaoRegistry dao,
        BankExtension bank,
        uint256 currentIndex,
        uint256 maxIndex,
        uint256 blockNumber,
        address token,
        uint256 amount
    ) internal {
        uint256 totalTokens = DaoHelper.priorTotalTokens(bank, blockNumber);
        // Distributes the funds to all unit holders of the DAO and ignores non-active members.
        // 将资金分配给 DAO 的所有单位持有人并忽略非活跃成员
        for (uint256 i = currentIndex; i < maxIndex; i++) {
             
            address memberAddr = dao.getMemberAddress(i);
             
            uint256 memberTokens = DaoHelper.priorMemberTokens(
                bank,
                memberAddr,
                blockNumber
            );
            if (memberTokens > 0) {
                 
                uint256 amountToDistribute = FairShareHelper.calc(
                    amount,
                    memberTokens,
                    totalTokens
                );

                if (amountToDistribute > 0) {
                     
                    bank.internalTransfer(
                        dao,
                        DaoHelper.ESCROW,
                        memberAddr,
                        token,
                        amountToDistribute
                    );
                }
            }
        }
    }
}
