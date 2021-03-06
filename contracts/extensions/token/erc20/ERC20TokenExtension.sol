// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "../../../core/DaoRegistry.sol";
import "../../../helpers/DaoHelper.sol";
import "../../IExtension.sol";
import "../../bank/Bank.sol";
import "./IERC20TransferStrategy.sol";
import "../../../guards/AdapterGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * ERC20Extension 为 内部代币 units 提供 erc20 合约功能
 */
contract ERC20Extension is AdapterGuard, IExtension, IERC20 {
    // 该扩展所属的 DAO 地址 
    DaoRegistry public dao;

    // 在 eip-1167 代理模式下 内部跟踪 部署
    bool public initialized = false;

    // 由 DAO 管理的用于跟踪 内部转账 的 代币地址
    address public tokenAddress;

    // DAO 管理的代币名称 
    string public tokenName;

    // 由 DAO 管理的代币的符号
    string public tokenSymbol;

    // DAO 管理的代币的小数位数
    uint8 public tokenDecimals;

    // Tracks all the token allowances: owner => spender => amount
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @notice 可克隆合约必须有一个空的构造函数
    constructor() {}

    /**
     * @notice 使用它所属的 DAO 初始化扩展 并检查是否设置了参数
     * @param _dao 拥有扩展的 DAO 的地址
     * @param creator DAO 和扩展的所有者， 也是 DAO 的成员  
     */
    function initialize(DaoRegistry _dao, address creator) external override {
        require(!initialized, "already initialized");
        require(_dao.isMember(creator), "not a member");
        require(tokenAddress != address(0x0), "missing token address");
        require(bytes(tokenName).length != 0, "missing token name");
        require(bytes(tokenSymbol).length != 0, "missing token symbol");
        initialized = true;
        dao = _dao;
    }

    /**
     * @dev 返回由跟踪内部传输的 DAO 管理的令牌地址。
     */
    function token() external view virtual returns (address) {
        return tokenAddress;
    }

    /**
     * @dev 如果扩展未初始化， 未保留且不为零，则设置令牌地址
     */
    function setToken(address _tokenAddress) external {
        // 是否预留
        bool not_reserved = DaoHelper.isNotReservedAddress(_tokenAddress);

        require(!initialized, "already initialized");
        require(_tokenAddress != address(0x0), "invalid token address");
        require(not_reserved, "token address already in use");

        tokenAddress = _tokenAddress;
    }

    /**
     * @dev 返回令牌的名称
     */
    function name() external view virtual returns (string memory) {
        return tokenName;
    }

    /**
     * @dev 如果扩展未初始化，则设置令牌的名称
     */
    function setName(string memory _name) external {
        require(!initialized, "already initialized");
        tokenName = _name;
    }

    /**
     * @dev 返回令牌的符号，通常是名称的较短版本
     */
    function symbol() external view virtual returns (string memory) {
        return tokenSymbol;
    }

    /**
     * @dev 如果扩展未初始化，则设置令牌符号
     */
    function setSymbol(string memory _symbol) external {
        require(!initialized, "already initialized");
        tokenSymbol = _symbol;
    }

    /**
     * @dev 返回用于获取其用户表示的小数位数 
     * 例如， 如果 `decimals` 等于 `2`， 则 `505` 代币的余额应该向用户显示为 `5,05` (`505 / 10 ** 2`)
     */
    function decimals() external view virtual returns (uint8) {
        return tokenDecimals;
    }

    /**
     * @dev 如果扩展未初始化，则设置标记小数
     */
    function setDecimals(uint8 _decimals) external {
        require(!initialized, "already initialized");
        tokenDecimals = _decimals;
    }

    /**
     * @dev 返回总令牌数量 `TOTAL`
     */
    function totalSupply() public view override returns (uint256) {
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        return bank.balanceOf(DaoHelper.TOTAL, tokenAddress);
    }

    /**
     * @dev 返回某账户下 `account` 拥有的 代币数量
     */
    function balanceOf(address account) public view override returns (uint256) {
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        return bank.balanceOf(account, tokenAddress);
    }

    /**
     * @dev 考虑 snapshot，返回 `account` 拥有的代币数量
     */
    function getPriorAmount(address account, uint256 snapshot)
        external
        view
        returns (uint256)
    {
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        return bank.getPriorAmount(account, tokenAddress, snapshot);
    }

    /**
    * @dev 返回 `spender` 将被允许通过 {transferFrom} 代表 `owner`  花费的剩余代币数量  这是默认情况下为零 
    * 当调用 {approve} 或 {transferFrom} 时，此值会发生变化
    */
    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    /**
     * @dev 将 `amount` 设置为 `spender` 在调用者代币上的限额 
     * @param spender 将减少单位的地址帐户
     * @param amount 从消费账户中减少的金额 
     * @return 一个布尔值，指示操作是否成功
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount)
        public
        override
        reentrancyGuard(dao)
        returns (bool)
    {
        address senderAddr = dao.getAddressIfDelegated(msg.sender);

        require(dao.isMember(senderAddr), "sender is not a member");

        require(
            DaoHelper.isNotZeroAddress(senderAddr),
            "ERC20: approve from the zero address"
        );

        require(
            DaoHelper.isNotZeroAddress(spender),
            "ERC20: approve to the zero address"
        );

        require(
            DaoHelper.isNotReservedAddress(spender),
            "spender can not be a reserved address"
        );

        _allowances[senderAddr][spender] = amount;

        emit Approval(senderAddr, spender, amount);

        return true;
    }

    /**
     * @dev 将 `amount` 令牌从调用者的账户转移到 `recipient`
     * @dev 传输操作遵循 ERC20_EXT_TRANSFER_TYPE 属性指定的 DAO 配置 
     * @param recipient 接收代币的地址帐户 
     * @param amount 代币的金额 
     * @return 一个布尔值，指示操作是否成功   
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        address senderAddr = dao.getAddressIfDelegated(msg.sender);

        return transferFrom(senderAddr, recipient, amount);
    }

    /**
     * @dev 使用 allowance mechanism 将 `amount` 令牌从 `sender` 转移到 `recipient`。然后从 caller 的 "allowance" 扣除 "amount" 
     * @dev 传输操作遵循 ERC20_EXT_TRANSFER_TYPE 属性指定的 DAO 配置
     * @param sender 将减少 units 的地址帐户
     * @param recipient 将接收 units 的地址帐户 
     * @param amount 金额 
     * @return 一个布尔值，指示操作是否成功
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) 
        public 
        override 
        returns (bool) 
    {

        require(DaoHelper.isNotZeroAddress(recipient), "ERC20: transfer to the zero address");

        address adapter = dao.getAdapterAddress(DaoHelper.TRANSFER_STRATEGY);

        IERC20TransferStrategy strategy = IERC20TransferStrategy(adapter);
        
        // allowedAmount： 允许转账的金额
        // approvalType： 授权类型
        (
            IERC20TransferStrategy.ApprovalType approvalType, uint256 allowedAmount
        ) = strategy.evaluateTransfer(
            dao,
            tokenAddress,
            sender,
            recipient,
            amount,
            msg.sender
        );

        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        // not allowed
        if (approvalType == IERC20TransferStrategy.ApprovalType.NONE) {
            revert("transfer not allowed");
        }
        // no limit
        if (approvalType == IERC20TransferStrategy.ApprovalType.SPECIAL) {
            _transferInternal(sender, recipient, amount, bank);

            emit Transfer(sender, recipient, amount);
            return true;
        }

        if (sender != msg.sender) {
            uint256 currentAllowance = _allowances[sender][msg.sender];

            require(
                currentAllowance >= amount,
                "ERC20: transfer amount exceeds allowance"
            );

            if (allowedAmount >= amount) {
                _allowances[sender][msg.sender] = currentAllowance - amount;
            }
        }

        if (allowedAmount >= amount) {
            _transferInternal(sender, recipient, amount, bank);

            emit Transfer(sender, recipient, amount);
            return true;
        }

        return false;
    }
    
    // 转移 内部代币
    // senderAddr 发送者
    // recipient 接收者
    // amount 金额
    // bank 金库
    function _transferInternal(address senderAddr, address recipient, uint256 amount, BankExtension bank) 
        internal 
    {
        DaoHelper.potentialNewMember(recipient, dao, bank);

        bank.internalTransfer(dao, senderAddr, recipient, tokenAddress, amount);
    }
}
