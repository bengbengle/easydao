pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/DaoRegistry.sol";


interface IReimbursement {
    function reimburseTransaction(
        DaoRegistry dao,
        address payable caller,
        uint256 gasUsage,
        uint256 spendLimitPeriod
    ) external;

    function shouldReimburse(DaoRegistry dao, uint256 gasLeft)
        external
        view
        returns (bool, uint256);
}
