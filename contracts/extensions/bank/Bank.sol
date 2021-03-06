// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../core/DaoRegistry.sol";
import "../IExtension.sol";
import "../../guards/AdapterGuard.sol";
import "../../helpers/DaoHelper.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract BankExtension is IExtension, ERC165 {
    using Address for address payable;
    using SafeERC20 for IERC20;

    // 可以存储在银行中的外部代币的最大数量
    uint8 public maxExternalTokens;

    // 在 eip-1167 代理模式下内部跟踪部署
    bool public initialized = false;
    DaoRegistry public dao;

    enum AclFlag {
        ADD_TO_BALANCE,
        SUB_FROM_BALANCE,
        INTERNAL_TRANSFER,
        WITHDRAW,
        REGISTER_NEW_TOKEN,
        REGISTER_NEW_INTERNAL_TOKEN,
        UPDATE_TOKEN
    }

    modifier noProposal() {
        require(dao.lockedAt() < block.number, "proposal lock");
        _;
    }

    /// @dev - Events for Bank
    event NewBalance(address member, address tokenAddr, uint160 amount);

    event Withdraw(address account, address tokenAddr, uint160 amount);

    event WithdrawTo(
        address accountFrom,
        address accountTo,
        address tokenAddr,
        uint160 amount
    );

    /*
     * STRUCTURES
     */
    // 用于 标记给定区块 的 投票数 的检查点
    struct Checkpoint {
        uint96 fromBlock;
        uint160 amount;
    }

    address[] public tokens;
    address[] public internalTokens;
    // tokenAddress => availability
    mapping(address => bool) public availableTokens;
    mapping(address => bool) public availableInternalTokens;
    // tokenAddress => memberAddress => checkpointNum => Checkpoint
    mapping(address => mapping(address => mapping(uint32 => Checkpoint)))
        public checkpoints;
    // tokenAddress => memberAddress => numCheckpoints
    mapping(address => mapping(address => uint32)) public numCheckpoints;

    constructor() {}

    modifier hasExtensionAccess(DaoRegistry _dao, AclFlag flag) {
        require(
            dao == _dao &&
                (address(this) == msg.sender ||
                    address(dao) == msg.sender ||
                    DaoHelper.isInCreationModeAndHasAccess(dao) ||
                    dao.hasAdapterAccessToExtension(
                        msg.sender,
                        address(this),
                        uint8(flag)
                    )),
            "bank::accessDenied:"
        );
        _;
    }

    /**
     * @notice 初始化 DAO
     * @dev 涉及初始化可用令牌、检查点和创建者的成员资格 ，只能调用一次
     * @param creator DAO 的创建者，他将成为初始成员
     */
    function initialize(DaoRegistry _dao, address creator) 
        external
        override 
    {
        require(!initialized, "bank already initialized");
        require(_dao.isMember(creator), "bank::not member");
        dao = _dao;
        initialized = true;

        availableInternalTokens[DaoHelper.UNITS] = true;
        internalTokens.push(DaoHelper.UNITS);

        availableInternalTokens[DaoHelper.MEMBER_COUNT] = true;
        internalTokens.push(DaoHelper.MEMBER_COUNT);

        uint256 nbMembers = _dao.getNbMembers();
        for (uint256 i = 0; i < nbMembers; i++) {
            addToBalance(
                _dao,
                _dao.getMemberAddress(i),
                DaoHelper.MEMBER_COUNT,
                1
            );
        }

        _createNewAmountCheckpoint(creator, DaoHelper.UNITS, 1);
        _createNewAmountCheckpoint(DaoHelper.TOTAL, DaoHelper.UNITS, 1);
    }

    function withdraw(
        DaoRegistry _dao,
        address payable member,
        address tokenAddr,
        uint256 amount
    ) external hasExtensionAccess(_dao, AclFlag.WITHDRAW) {
        require(balanceOf(member, tokenAddr) >= amount, "bank::withdraw::not enough funds");
        
        subtractFromBalance(_dao, member, tokenAddr, amount);
        
        if (tokenAddr == DaoHelper.ETH_TOKEN) {
            member.sendValue(amount);
        } else {
            IERC20(tokenAddr).safeTransfer(member, amount);
        }

        emit Withdraw(member, tokenAddr, uint160(amount));
    }

    function withdrawTo(
        DaoRegistry _dao,
        address memberFrom,
        address payable memberTo,
        address tokenAddr,
        uint256 amount
    ) external hasExtensionAccess(_dao, AclFlag.WITHDRAW) {
        require(
            balanceOf(memberFrom, tokenAddr) >= amount,
            "bank::withdraw::not enough funds"
        );
        subtractFromBalance(_dao, memberFrom, tokenAddr, amount);
        if (tokenAddr == DaoHelper.ETH_TOKEN) {
            memberTo.sendValue(amount);
        } else {
            IERC20(tokenAddr).safeTransfer(memberTo, amount);
        }

        emit WithdrawTo(memberFrom, memberTo, tokenAddr, uint160(amount));
    }

    /**
     * @return 给定的令牌是否是有效的 内部令牌
     * @param token 要查找的令牌地址
     */
    function isInternalToken(address token) external view returns (bool) {
        return availableInternalTokens[token];
    }

    /**
     * @return 给定的令牌 是否是有效的 令牌
     * @param token 要查找的令牌地址
     */
    function isTokenAllowed(address token) public view returns (bool) {
        return availableTokens[token];
    }

    /**
     * @notice 设置银行允许的最大 external 代币数量
     * @param maxTokens 允许的最大令牌数量
     */
    function setMaxExternalTokens(uint8 maxTokens) external {
        require(!initialized, "bank already initialized");
        require(
            maxTokens > 0 && maxTokens <= DaoHelper.MAX_TOKENS_GUILD_BANK,
            "max number of external tokens should be (0,200)"
        );
        maxExternalTokens = maxTokens;
    }

    /*
     * BANK
     */

    /**
     * @notice 在银行 注册 一个 新代币
     * @dev 不能是保留令牌或可用的内部令牌
     * @param token 代币地址
     */
    function registerPotentialNewToken(DaoRegistry _dao, address token)
        external
        hasExtensionAccess(_dao, AclFlag.REGISTER_NEW_TOKEN)
    {
        require(DaoHelper.isNotReservedAddress(token), "reservedToken");
        require(!availableInternalTokens[token], "internalToken");
        require(
            tokens.length <= maxExternalTokens,
            "exceeds the maximum tokens allowed"
        );

        if (!availableTokens[token]) {
            availableTokens[token] = true;
            tokens.push(token);
        }
    }

    /**
     * @notice 在银行注册一个潜在的 新 内部代币
     * @dev 不能是保留令牌或可用令牌
     * @param token 代币地址
     */
    function registerPotentialNewInternalToken(DaoRegistry _dao, address token)
        external
        hasExtensionAccess(_dao, AclFlag.REGISTER_NEW_INTERNAL_TOKEN)
    {
        require(DaoHelper.isNotReservedAddress(token), "reservedToken");
        require(!availableTokens[token], "availableToken");

        if (!availableInternalTokens[token]) {
            availableInternalTokens[token] = true;
            internalTokens.push(token);
        }
    }

    function updateToken(DaoRegistry _dao, address tokenAddr)
        external
        hasExtensionAccess(_dao, AclFlag.UPDATE_TOKEN)
    {
        require(isTokenAllowed(tokenAddr), "token not allowed");
        uint256 totalBalance = balanceOf(DaoHelper.TOTAL, tokenAddr);

        uint256 realBalance;

        if (tokenAddr == DaoHelper.ETH_TOKEN) {
            realBalance = address(this).balance;
        } else {
            IERC20 erc20 = IERC20(tokenAddr);
            realBalance = erc20.balanceOf(address(this));
        }

        if (totalBalance < realBalance) {

            addToBalance(_dao, DaoHelper.GUILD, tokenAddr, realBalance - totalBalance);
        
        } else if (totalBalance > realBalance) {

            uint256 tokensToRemove = totalBalance - realBalance;

            uint256 guildBalance = balanceOf(DaoHelper.GUILD, tokenAddr);
            
            if (guildBalance > tokensToRemove) {
                
                subtractFromBalance(_dao, DaoHelper.GUILD, tokenAddr, tokensToRemove);
            
            } else {

                subtractFromBalance(_dao, DaoHelper.GUILD, tokenAddr, guildBalance);
            }
        }
    }

    /**
     * Public read-only functions
     */

    /**
     * Internal bookkeeping
     */

    /**
     * @return 来自给定索引的银行的代币
     * @param index 要在银行代币中查找的索引
     */
    function getToken(uint256 index) external view returns (address) {
        return tokens[index];
    }

    /**
     * @return 银行中的代币地址总数, token numbers
     */
    function nbTokens() external view returns (uint256) {
        return tokens.length;
    }

    /**
     * @return 所有在银行注册的代币 
     */
    function getTokens() external view returns (address[] memory) {
        return tokens;
    }

    /**
     * @return 给定索引处的内部令牌
     * @param index 要在银行内部令牌数组中查找的索引
     */
    function getInternalToken(uint256 index) external view returns (address) {
        return internalTokens[index];
    }

    /**
     * @return 银行内部代币地址数量
     */
    function nbInternalTokens() external view returns (uint256) {
        return internalTokens.length;
    }

    /**
     * @notice 添加给定令牌的成员余额
     * @param member 余额将被更新的成员
     * @param token 要更新的令牌
     * @param amount 新余额
     */
    function addToBalance(DaoRegistry _dao, address member, address token, uint256 amount) 
        public 
        payable 
        hasExtensionAccess(_dao, AclFlag.ADD_TO_BALANCE) 
    {
        require(
            availableTokens[token] || availableInternalTokens[token],
            "unknown token address"
        );

        uint256 newAmount = balanceOf(member, token) + amount;
        uint256 newTotalAmount = balanceOf(DaoHelper.TOTAL, token) + amount;

        _createNewAmountCheckpoint(member, token, newAmount);
        _createNewAmountCheckpoint(DaoHelper.TOTAL, token, newTotalAmount);
    }

    /**
     * @notice 从给定令牌的成员余额中
     * @param _dao 指定 _dao
     * @param member 余额将被更新的成员 
     * @param token 要更新的令牌 
     * @param amount 新余额
     */
    function subtractFromBalance(
        DaoRegistry _dao,
        address member,
        address token,
        uint256 amount
    ) public hasExtensionAccess(_dao, AclFlag.SUB_FROM_BALANCE) {
        uint256 newAmount = balanceOf(member, token) - amount;
        uint256 newTotalAmount = balanceOf(DaoHelper.TOTAL, token) - amount;

        _createNewAmountCheckpoint(member, token, newAmount);
        _createNewAmountCheckpoint(DaoHelper.TOTAL, token, newTotalAmount);
    }

    /**
     * @notice 进行内部代币转移
     * @param from 发送代币的成员
     * @param to 接收代币的成员
     * @param amount 新的转账金额
     */
    function internalTransfer(DaoRegistry _dao, address from, address to, address token, uint256 amount) 
        external 
        hasExtensionAccess(_dao, AclFlag.INTERNAL_TRANSFER) 
    {
        uint256 newAmount = balanceOf(from, token) - amount;
        uint256 newAmount2 = balanceOf(to, token) + amount;

        _createNewAmountCheckpoint(from, token, newAmount);
        _createNewAmountCheckpoint(to, token, newAmount2);
    }

    /**
     * @notice 返回给定代币的 余额
     * @param member 要查找的地址
     * @param tokenAddr token 地址
     * @return 账户的 tokenAddr 余额中的金额
     */
    function balanceOf(address member, address tokenAddr)
        public
        view
        returns (uint160)
    {
        uint32 nCheckpoints = numCheckpoints[tokenAddr][member];
        return
            nCheckpoints > 0 ? checkpoints[tokenAddr][member][nCheckpoints - 1].amount : 0;
    }

    /**
     * @notice 确定 一个账户 在 某区块号之前 的 投票数， 区块号必须是确定的区块， 否则此功能将 恢复以防止错误信息  
     * @param account 要检查的账户地址 
     * @param blockNumber 获得投票余额的区块号 
     * @return 账户在给定区块中的 投票数
     */
    function getPriorAmount(address account, address tokenAddr, uint256 blockNumber) 
        external 
        view returns (uint256) 
    {
        require(
            blockNumber < block.number,
            "Uni::getPriorAmount: not yet determined"
        );

        uint32 nCheckpoints = numCheckpoints[tokenAddr][account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // 首先检查最近的余额
        if (
            checkpoints[tokenAddr][account][nCheckpoints - 1].fromBlock <= blockNumber
        ) {
            return checkpoints[tokenAddr][account][nCheckpoints - 1].amount;
        }

        // 接下来检查 隐式 零余额
        if (checkpoints[tokenAddr][account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[tokenAddr][account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.amount;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[tokenAddr][account][lower].amount;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            super.supportsInterface(interfaceId) ||
            this.subtractFromBalance.selector == interfaceId ||
            this.addToBalance.selector == interfaceId ||
            this.getPriorAmount.selector == interfaceId ||
            this.balanceOf.selector == interfaceId ||
            this.internalTransfer.selector == interfaceId ||
            this.nbInternalTokens.selector == interfaceId ||
            this.getInternalToken.selector == interfaceId ||
            this.getTokens.selector == interfaceId ||
            this.nbTokens.selector == interfaceId ||
            this.getToken.selector == interfaceId ||
            this.updateToken.selector == interfaceId ||
            this.registerPotentialNewInternalToken.selector == interfaceId ||
            this.registerPotentialNewToken.selector == interfaceId ||
            this.setMaxExternalTokens.selector == interfaceId ||
            this.isTokenAllowed.selector == interfaceId ||
            this.isInternalToken.selector == interfaceId ||
            this.withdraw.selector == interfaceId ||
            this.withdrawTo.selector == interfaceId;
    }

    /**
     * @notice 为某个成员的代币创建一个新的金额检查点
     * @dev 如果数量大于 2**64-1，则还原
     * @param member 将添加检查点的成员
     * @param token 需要更改余额的token
     * @param amount 要写入新检查点的金额
     */
    function _createNewAmountCheckpoint(
        address member,
        address token,
        uint256 amount
    ) internal {
        bool isValidToken = false;
        if (availableInternalTokens[token]) {
            // 代币数量超过内部代币的最大限额
            require(
                amount < type(uint88).max,
                "token amount exceeds the maximum limit for internal tokens"
            );

            isValidToken = true;
        } else if (availableTokens[token]) {
            //代币数量超过外部代币的最大限制
            require(
                amount < type(uint160).max,
                "token amount exceeds the maximum limit for external tokens"
            );

            isValidToken = true;
        }
        require(isValidToken, "token not registered");

        uint160 newAmount = uint160(amount);

        uint32 nCheckpoints = numCheckpoints[token][member];

        // 当 block.number 与 fromBlock 值完全匹配时，允许数量更新， 否则 应该生成一个新的检查点
        // checkpoints[token][member][nCheckpoints - 1].fromBlock, 最后检查点对应的区块号
        if (
            nCheckpoints > 0 && checkpoints[token][member][nCheckpoints - 1].fromBlock == block.number
        ) {
            checkpoints[token][member][nCheckpoints - 1].amount = newAmount;
        } else {
            checkpoints[token][member][nCheckpoints] = Checkpoint(uint96(block.number), newAmount);
            
            numCheckpoints[token][member] = nCheckpoints + 1;
        }

        emit NewBalance(member, token, newAmount);
    }
}
