pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT
import "../../../core/DaoRegistry.sol";
import "../../../helpers/DaoHelper.sol";
import "../../bank/Bank.sol";
import "./IERC20TransferStrategy.sol";
import "./InternalTokenVestingExtension.sol";

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

/**
 * ERC20Extension 是为 DAO 成员持有的内部代币
 */
contract ERC20TransferStrategySimple is IERC20TransferStrategy {

    bytes32 public constant ERC20_EXT_TRANSFER_TYPE = keccak256("erc20.transfer.type");

    // @notice 可克隆合约必须有一个空的构造函数
    // constructor() {}

    function hasBankAccess(DaoRegistry dao, address caller)
        public
        view
        returns (bool)
    {
        return
            dao.hasAdapterAccessToExtension(
                caller,
                dao.getExtensionAddress(DaoHelper.BANK),
                uint8(BankExtension.AclFlag.INTERNAL_TRANSFER)
            );
    }

    function evaluateTransfer(
        DaoRegistry dao,
        address,
        address,
        address to,
        uint256 amount,
        address caller
    ) external view override returns (ApprovalType, uint256) {
        // 如果转移是内部转移， 则使其无限制
        if (hasBankAccess(dao, caller)) {
            return (ApprovalType.SPECIAL, amount);
        }

        uint256 transferType = dao.getConfiguration(ERC20_EXT_TRANSFER_TYPE);
        // member only
        if (transferType == 0 && dao.isMember(to)) {
            // members only transfer
            return (ApprovalType.STANDARD, amount);
            // open transfer
        } else if (transferType == 1) {
            return (ApprovalType.STANDARD, amount);
        }
        // transfer not allowed，
        return (ApprovalType.NONE, 0);
    }
}
