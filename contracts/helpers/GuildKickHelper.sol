pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../guards/MemberGuard.sol";
import "../adapters/interfaces/IVoting.sol";
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

library GuildKickHelper {
    address internal constant TOTAL = address(0xbabe);
    address internal constant UNITS = address(0xFF1CE);
    address internal constant LOCKED_UNITS = address(0xFFF1CE);
    address internal constant LOOT = address(0xB105F00D);
    address internal constant LOCKED_LOOT = address(0xBB105F00D);

    bytes32 internal constant BANK = keccak256("bank");
    address internal constant GUILD = address(0xdead);

    function lockMemberTokens(DaoRegistry dao, address potentialKickedMember)
        internal
    {
        // Get the bank extension
        BankExtension bank = BankExtension(dao.getExtensionAddress(BANK));
        // Calculates the total units, loot and locked loot before any internal transfers
        // it considers the locked loot to be able to calculate the fair amount to ragequit,
        // but locked loot can not be burned.
        // 在任何内部转移之前计算总单位、战利品和锁定战利品 
        // 它认为锁定的战利品能够计算公平的 ragequit 数量， 
        // 但是锁定的战利品不能被烧毁。

        uint256 unitsToBurn = bank.balanceOf(potentialKickedMember, UNITS);
        uint256 lootToBurn = bank.balanceOf(potentialKickedMember, LOOT);

        bank.registerPotentialNewToken(dao, LOCKED_UNITS);
        bank.registerPotentialNewToken(dao, LOCKED_LOOT);

        bank.addToBalance(
            dao,
            potentialKickedMember,
            LOCKED_UNITS,
            unitsToBurn
        );
        bank.subtractFromBalance(
            dao,
            potentialKickedMember,
            UNITS,
            unitsToBurn
        );

        bank.addToBalance(dao, potentialKickedMember, LOCKED_LOOT, lootToBurn);
        bank.subtractFromBalance(dao, potentialKickedMember, LOOT, lootToBurn);
    }

    function unlockMemberTokens(DaoRegistry dao, address kickedMember)
        internal
    {
        BankExtension bank = BankExtension(dao.getExtensionAddress(BANK));

        uint256 unitsToReturn = bank.balanceOf(kickedMember, LOCKED_UNITS);
        uint256 lootToReturn = bank.balanceOf(kickedMember, LOCKED_LOOT);

        bank.addToBalance(dao, kickedMember, UNITS, unitsToReturn);
        bank.subtractFromBalance(
            dao,
            kickedMember,
            LOCKED_UNITS,
            unitsToReturn
        );

        bank.addToBalance(dao, kickedMember, LOOT, lootToReturn);
        bank.subtractFromBalance(dao, kickedMember, LOCKED_LOOT, lootToReturn);
    }

    /**
     * @notice 根据当前的踢球提案 id 将资金从公会帐户转移到被踢的成员帐户。 
     * @notice 资金金额以会员实际余额计算，以确保会员没有退票。 
     * @dev 踢球提案必须正在进行中。 
     * @dev 每个 DAO 一次只能执行一个 kick。 
     * @dev 只有活跃成员才能被踢出。 
     * @dev 只有通过投票过程的提案才能完成。 
     * @param dao dao 地址。
     */
    function rageKick(DaoRegistry dao, address kickedMember) internal {

        BankExtension bank = BankExtension(dao.getExtensionAddress(BANK));
        uint256 nbTokens = bank.nbTokens();

        // 在任何内部转移之前计算总单位、战利品和锁定战利品它认为锁定的战利品能够计算公平的 ragequit 数量，但是锁定的战利品不能被烧毁。
        uint256 initialTotalTokens = DaoHelper.totalTokens(bank);

        uint256 unitsToBurn = bank.balanceOf(kickedMember, LOCKED_UNITS);
        uint256 lootToBurn = bank.balanceOf(kickedMember, LOCKED_LOOT);
        uint256 unitsAndLootToBurn = unitsToBurn + lootToBurn;

        if (unitsAndLootToBurn > 0) {
            // 将资金从内部公会账户转移到内部会员账户。
            for (uint256 i = 0; i < nbTokens; i++) {
                 
                address token = bank.getToken(i);

                // 根据代币、单位和战利品计算公平的资金数额。创建踢球提案时考虑了历史公会余额。
                 
                uint256 amountToRagequit = FairShareHelper.calc(
                    bank.balanceOf(GUILD, token),
                    unitsAndLootToBurn,
                    initialTotalTokens
                );

                // 如果用户有足够的资金来接收，则只执行内部转账。
                if (amountToRagequit > 0) {
                    // 气体优化以允许更高的最大令牌限制， 这里故意不使用安全数学来防止溢出阻止函数执行 
                    // 如果令牌溢出（这会打破狂暴）， 这是因为供应被人为地夸大到被遗忘，所以我们可能无论如何都不关心它
                     
                    bank.internalTransfer(
                        dao,
                        GUILD,
                        kickedMember,
                        token,
                        amountToRagequit
                    );
                }
            }

            bank.subtractFromBalance(
                dao,
                kickedMember,
                LOCKED_UNITS,
                unitsToBurn
            );
            bank.subtractFromBalance(
                dao,
                kickedMember,
                LOCKED_LOOT,
                lootToBurn
            );
        }
    }
}
