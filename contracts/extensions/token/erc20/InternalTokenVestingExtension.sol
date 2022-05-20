pragma solidity ^0.8.0;


import "../../../core/DaoRegistry.sol";
import "../../../extensions/IExtension.sol";
import "../../../helpers/DaoHelper.sol";

contract InternalTokenVestingExtension is IExtension {
    enum AclFlag {
        NEW_VESTING,
        REMOVE_VESTING
    }

    bool private _initialized;

    DaoRegistry private _dao;

    struct VestingSchedule {
        uint64 startDate;
        uint64 endDate;
        uint88 blockedAmount;
    }

    modifier hasExtensionAccess(DaoRegistry dao, AclFlag flag) {
        bool isInCreation = DaoHelper.isInCreationModeAndHasAccess(_dao);
        
        /**
        * @notice 调用者是 adapter 并且 有权 访问此 ext 
        * @param adapterAddress msg.sender
        * @param extensionAddress address(this)
        * @param flag unit8 权限标识
        */
        bool hasAdapterAccess = _dao.hasAdapterAccessToExtension(
            msg.sender,
            address(this),
            uint8(flag)
        );

        bool hasAccess = isInCreation || hasAdapterAccess;

        require(dao == _dao && hasAccess, "vestingExt::accessDenied");

        _;
    }

    mapping(address => mapping(address => VestingSchedule)) public vesting;

    /// @notice Clonable contract must have an empty constructor
    constructor() {}

    /**
     * @notice 用它所属的 DAO 初始化扩展 
     * @param dao 拥有扩展的 DAO 的地址
     */
    function initialize(DaoRegistry dao, address) external override {
        require(!_initialized, "vestingExt::already initialized");
        _initialized = true;
        _dao = dao;
    }

    /**
     * @notice 根据 内部代币、金额 和 结束日期 为成员创建新的 归属计划 
     * @param member 更新余额的成员地址
     * @param internalToken 成员接收资金的内部 DAO 代币 
     * @param amount 质押金额
     * @param endDate 归属计划结束的 unix 时间戳
     */
    function createNewVesting(DaoRegistry dao, address member, address internalToken, uint88 amount, uint64 endDate) 
        external 
        hasExtensionAccess(dao, AclFlag.NEW_VESTING) 
    {
        require(endDate > block.timestamp, "vestingExt::end date in the past");
        
        // 仍然锁定的金额
        VestingSchedule storage schedule = vesting[member][internalToken];
        uint88 minBalance = getMinimumBalanceInternal(schedule.startDate, schedule.endDate, schedule.blockedAmount);

        schedule.startDate = uint64(block.timestamp);

        // 获取上次质押过的时间  get max value between endDate and previous one
        if (endDate > schedule.endDate) {
            schedule.endDate = endDate;
        }

        schedule.blockedAmount = minBalance + amount;
    }

    /**
     * @notice 根据 内部代币 和 金额 更新成员的 归属时间表 
     * @param member 成员地址 
     * @param internalToken 内部 DAO 代币  
     * @param amountToRemove 数量
     */
    function removeVesting(DaoRegistry dao, address member, address internalToken, uint88 amountToRemove) 
        external 
        hasExtensionAccess(dao, AclFlag.REMOVE_VESTING) 
    {
        VestingSchedule storage schedule = vesting[member][internalToken];
        uint88 blockedAmount = getMinimumBalanceInternal(
            schedule.startDate,
            schedule.endDate,
            schedule.blockedAmount
        );

        schedule.startDate = uint64(block.timestamp);
        schedule.blockedAmount = blockedAmount - amountToRemove;
    }

    /**
     * @notice 返回 给定成员 和 内部代币 的最低 归属余额 / 不可归属的金额，仍然 锁定金额
     * @param member 更新余额的 成员地址 
     * @param internalToken 成员 接收资金的 内部 DAO 代币
     */
    function getMinimumBalance(address member, address internalToken)
        external
        view
        returns (uint88)
    {
        VestingSchedule storage schedule = vesting[member][internalToken];
        return
            getMinimumBalanceInternal(schedule.startDate, schedule.endDate, schedule.blockedAmount);
    }

    /**
     * @notice 返回给定 开始日期、结束日期 和 金额 的 最低归属余额 
     * @param startDate 归属的开始日期 用于计算经过的时间 
     * @param endDate 归属的结束日期， 用于计算归属期 
     * @param amount 质押金额
     */
    function getMinimumBalanceInternal(
        uint64 startDate,
        uint64 endDate,
        uint88 amount
    ) public view returns (uint88) {
        if (block.timestamp > endDate) {
            return 0;
        }
        // 质押期
        uint88 period = endDate - startDate;
        
        // 已质押的 时间
        uint88 elapsedTime = uint88(block.timestamp) - startDate;
        
        // 按比例 已归属金额
        uint88 vestedAmount = (amount * elapsedTime) / period;

        // 未归属的金额/ 仍然质押的金额
        return amount - vestedAmount;
    }
}
