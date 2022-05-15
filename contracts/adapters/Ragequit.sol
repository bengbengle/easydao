pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "./interfaces/IRagequit.sol";
import "../helpers/FairShareHelper.sol";
import "../helpers/DaoHelper.sol";
import "../guards/AdapterGuard.sol";

contract RagequitContract is IRagequit, AdapterGuard {
    /**
     * @notice Event emitted when a member of the DAO executes a ragequit with all or parts of the member's units/loot.
     */
    event MemberRagequit(
        address daoAddress,
        address memberAddr,
        uint256 burnedUnits,
        uint256 burnedLoot,
        uint256 initialTotalUnitsAndLoot
    );

    /**
     * @notice 允许 DAO 的成员或顾问通过按比例销毁成员的单位/战利品来选择退出
     * @notice 任何人都可以调用此函数，但只有拥有单位的成员和顾问才能执行整个 ragequit 过程 
     * @notice 执行本次调用前需要对token数组进行升序排序，否则交易会失败
     * @dev unitsToBurn 和 lootToBurn 之和必须大于零
     * @dev 一旦所有单位/战利品都被烧毁，该成员将成为 DAO 的非活动成员 
     * @dev 如果成员提供了无效/不允许的令牌，则整个处理的都将被还原
     * @dev 如果没有通知令牌，则交易被还原
     * @param dao 成员所属的 dao 地址
     * @param unitsToBurn 必须转换为资金的成员单位数量 
     * @param lootToBurn 必须转换为资金的成员战利品数量 
     * @param tokens 资金应该发送到的令牌数组
     */
    function ragequit(
        DaoRegistry dao,
        uint256 unitsToBurn,
        uint256 lootToBurn,
        address[] calldata tokens
    ) external override reentrancyGuard(dao) {
        
        // At least one token needs to be provided
        require(tokens.length > 0, "missing tokens");
        
        // 检查是否有足够的 unit 和/或 loot 可以燃烧
        require(unitsToBurn + lootToBurn > 0, "insufficient units/loot");
        
        // 获取委托地址，否则返回发件人地址
        address memberAddr = DaoHelper.msgSender(dao, msg.sender);

        // 实例化银行扩展以处理内部余额检查和转账
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        // 检查成员是否有足够的 units 来燃烧
        require(
            bank.balanceOf(memberAddr, DaoHelper.UNITS) >= unitsToBurn,
            "insufficient units"
        );
        // 检查成员是否有足够的 loot 可以燃烧
        require(
            bank.balanceOf(memberAddr, DaoHelper.LOOT) >= lootToBurn,
            "insufficient loot"
        );

        // 更新会员的 内部账户余额， 开始 ragequit 流程
        _prepareRagequit(
            dao,
            memberAddr,
            unitsToBurn,
            lootToBurn,
            tokens,
            bank
        );
    }

    /**
     * @notice 从内部成员的账户中减去 成比例的 units 或 loot
     * @param memberAddr 想要烧掉 units 或 loot 的成员地址
     * @param unitsToBurn 必须转换为资金的成员 units 数量
     * @param lootToBurn 必须转换为资金的成员 loot 数量
     * @param tokens 资金应该发送到的 tokens 数组 
     * @param bank 银行扩展名
     */
    function _prepareRagequit(
        DaoRegistry dao,
        address memberAddr,
        uint256 unitsToBurn,
        uint256 lootToBurn,
        address[] memory tokens,
        BankExtension bank
    ) internal {
        // 在任何内部转账 之前计算总的 units、loot 和 locked loot
        // 它认为 locked 的 loot 能够计算公平的 ragequit 数量， 但是 locked loot 是不能被烧毁的
        // 全部代币数量
        uint256 totalTokens = DaoHelper.totalTokens(bank);

        // 从成员账户中减去要 burn 的 units 的数量
        bank.internalTransfer(
            dao,
            memberAddr,
            DaoHelper.GUILD,
            DaoHelper.UNITS,
            unitsToBurn
        );
        // 从成员账户中减去要 burn 的 loot 的数量
        bank.internalTransfer(
            dao,
            memberAddr,
            DaoHelper.GUILD,
            DaoHelper.LOOT,
            lootToBurn
        );

        // 通过基于每个提供的令牌更新 GUILD 内部余额来完成 ragequit 过程
        _burnUnits(
            dao,
            memberAddr,
            unitsToBurn,
            lootToBurn,
            totalTokens,
            tokens,
            bank
        );
    }

    /**
     * @notice 从银行账户中减去相应比例的 loot / units
     * @notice 并根据提供的代币将资金转入会员的内部账户
     * @param memberAddr 想要烧毁单位和/或战利品的 账户地址
     * @param unitsToBurn 必须转换为资金的成员 units 数量
     * @param lootToBurn 必须转换为资金的成员 loot 数量
     * @param initialTotalUnitsAndLoot 内部转移前的 units 和 loot 总和
     * @param tokens 资金应发送到的令牌数组
     * @param bank The bank extension.
     */
    function _burnUnits(
        DaoRegistry dao,
        address memberAddr,
        uint256 unitsToBurn,
        uint256 lootToBurn,
        uint256 initialTotalUnitsAndLoot,
        address[] memory tokens,
        BankExtension bank
    ) internal {
        // 计算要燃烧的 loot 和 units 的总量
        uint256 unitsAndLootToBurn = unitsToBurn + lootToBurn;

        // 根据会员提供的每个代币，将资金从内部公会账户转移到内部会员账户 
        // 所提供的代币必须得到公会银行的支持/允许，否则会恢复整个交易
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; i++) {
            address currentToken = tokens[i];
            uint256 j = i + 1;
            if (j < length) {
                // 下一个令牌需要大于当前令牌以防止重复
                require(currentToken < tokens[j], "duplicate token");
            }

            // 检查公会银行是否支持 此令牌

            require(bank.isTokenAllowed(currentToken), "token not allowed");

            // 根据 代币、单位 和 loot 计算公平的 资金数额
            uint256 amountToRagequit = FairShareHelper.calc(
                bank.balanceOf(DaoHelper.GUILD, currentToken),
                unitsAndLootToBurn,
                initialTotalUnitsAndLoot
            );

            if (amountToRagequit > 0) {
                bank.internalTransfer(
                    dao,
                    DaoHelper.GUILD,
                    memberAddr,
                    currentToken,
                    amountToRagequit
                );
            }
        }

        // 一旦 units 和 loot 被烧毁， 资金也转移完成， 发出一个事件以指示操作成功
        emit MemberRagequit(
            address(dao),
            memberAddr,
            unitsToBurn,
            lootToBurn,
            initialTotalUnitsAndLoot
        );
    }
}
