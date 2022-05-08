pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "../helpers/DaoHelper.sol";

abstract contract MemberGuard {
    /**
     * @dev Only members of the DAO are allowed to execute the function call.
     * @dev 只允许 DAO 的成员执行函数调用
     */
    modifier onlyMember(DaoRegistry dao) {
        _onlyMember(dao, msg.sender);
        _;
    }

    modifier onlyMember2(DaoRegistry dao, address _addr) {
        _onlyMember(dao, _addr);
        _;
    }

    function _onlyMember(DaoRegistry dao, address _addr) internal view {
        require(isActiveMember(dao, _addr), "onlyMember");
    }

    function isActiveMember(DaoRegistry dao, address _addr)
        public
        view
        returns (bool)
    {
        address bankAddress = dao.extensions(DaoHelper.BANK);

        if (bankAddress != address(0x0)) {
            address memberAddr = DaoHelper.msgSender(dao, _addr);
            uint256 amount = BankExtension(bankAddress).balanceOf(
                memberAddr,
                DaoHelper.UNITS
            );

            return dao.isMember(_addr) && amount > 0;
        }

        return dao.isMember(_addr);
    }
}
