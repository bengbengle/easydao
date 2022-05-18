pragma solidity ^0.8.0;



import "../core/DaoRegistry.sol";
import "../guards/AdapterGuard.sol";
import "./modifiers/Reimbursable.sol";
import "../adapters/interfaces/IVoting.sol";
import "../adapters/interfaces/IDistribute.sol";
import "../helpers/FairShareHelper.sol";
import "../helpers/DaoHelper.sol";
import "../extensions/bank/Bank.sol";

contract DistributeContract is IDistribute, AdapterGuard, Reimbursable {

    // 表示分发过程已经完成的事件 
    event Distributed(
        address daoAddress,
        address token,
        uint256 amount,
        address unitHolder
    );

    // distribution 状态
    enum DistributionStatus {
        NOT_STARTED,
        IN_PROGRESS,
        DONE,
        FAILED
    }

    // distribution 提案的状态
    struct Distribution {
        // 代币地址
        address token;

        // 金额
        uint256 amount;

        // 将接收 资金的 成员地址 如果为 0x0，资金将分配给 DAO 的所有成员
        address unitHolderAddr;
        
        // 状态 
        DistributionStatus status;
        
        // 当前迭代索引来控制缓存的for循环
        uint256 currentIndex;
        
        // 创建提案的区块号
        uint256 blockNumber;
    }

    // 跟踪每个 DAO 执行的所有分发， Dao Addr --> mapping { proposalId --> Distribution } 
    mapping(address => mapping(bytes32 => Distribution)) public distributions;

    // 跟踪每个 DAO 的最新正在进行的分发提案，以确保一次只能处理 1 个提案, dao addr --> proposalId
    mapping(address => bytes32) public ongoingDistributions;

    /**
     * @notice 为 DAO 的一个或所有成员创建 分发提案，打开它进行投票，并赞助它 
     * @dev 只接受银行允许的代币， 如果 unitHolderAddr 为 0x0，则资金将分配给 DAO 的所有成员， 提案 ID 不能重复使用， 金额必须大于零 
     * @param dao dao 地址 
     * @param proposalId 分发提案 ID 
     * @param unitHolderAddr 应收到资金的成员地址，如果为0x0，资金将分配给DAO的所有成员 
     * @param token 成员应该收到资金的分发代币必须得到 DAO 的支持 
     * @param amount 要分配的金额 
     * @param data 与分配提案相关的附加信息
     * @param token 成员应收到资金的分配代币必须得到 DAO 的支持
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

        // 保存提案的状态
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
     * @notice 处理分配方案，根据单位持有量计算分配给会员的公平金额 
     * @dev 分发提案提案必须正在进行中 
     * @dev 每个 DAO 一次只能执行一个提案 
     * @dev 只有活跃会员才能收到资金 
     * @dev 只有通过投票的提案才能设置为进行中状态 
     * @param dao dao 地址 
     * @param proposalId 分发提案 ID
     */
    // 使用 reentrancyGuard 防止函数重入，这可以防止 DAO 注册表中的并发修改
     
    function processProposal(DaoRegistry dao, bytes32 proposalId)
        external
        override
        reimbursable(dao)
    {
        dao.processProposal(proposalId);

        // 检查提案是否存在或尚未进行中
        Distribution storage distribution = distributions[address(dao)][
            proposalId
        ];
        require(
            distribution.status == DistributionStatus.NOT_STARTED,
            "proposal already completed or in progress"
        );

        // 检查是否有正在进行的提案，一次只能执行一个提案
        bytes32 ongoingProposalId = ongoingDistributions[address(dao)];
        require(
            ongoingProposalId == bytes32(0) ||
                distributions[address(dao)][ongoingProposalId].status !=
                DistributionStatus.IN_PROGRESS,
            "another proposal already in progress"
        );

        // 检查提案是否通过
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
     * @notice 将资金从公会账户转移到会员的内部账户 
     * @notice 资金金额以每个会员的历史单位数计算 
     * @dev 分发提案必须正在进行中 
     * @dev 只有通过投票的提案才能完成 
     * @dev 只有活跃会员才能收到资金 
     * @param dao dao 地址 
     * @param toIndex 控制缓存的for循环的索引
     */

    function distribute(DaoRegistry dao, uint256 toIndex)
        external
        override
        reimbursable(dao)
    {
        // 检查提案是否不存在或尚未完成
        bytes32 ongoingProposalId = ongoingDistributions[address(dao)];
        Distribution storage distribution = distributions[address(dao)][
            ongoingProposalId
        ];
        uint256 blockNumber = distribution.blockNumber;
        require(
            distribution.status == DistributionStatus.IN_PROGRESS,
            "distrib completed or not exist"
        );

        // 检查给定的索引是否已经被处理
        uint256 currentIndex = distribution.currentIndex;
        require(currentIndex <= toIndex, "toIndex too low");

        address token = distribution.token;
        uint256 amount = distribution.amount;

        // 获取处理提案时的总单位数
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
            // 根据成员数设置支持的最大索引
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
     * @notice 使用基于令牌参数的金额更新持有人帐户, 这是仅在 银行分发中发生的内部转账
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
        // 只给 1 个地址分发资金
        bank.internalTransfer(
            dao,
            DaoHelper.ESCROW,
            unitHolderAddr,
            token,
            amount
        );
    }

    /**
     * @notice 使用基于 token 参数的金额更新所有持有人账户， 这是仅在银行分机中发生的内部转账
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

        // 将资金分配给 DAO 的所有单位持有人， 忽略 非活跃成员
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
