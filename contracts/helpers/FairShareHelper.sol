pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

library FairShareHelper {
    /**
     * @notice calculates the fair unit amount based the total units and current balance.
     * @notice 根据总 unit 和当前 balance 计算 fair unit 数量
     */
    function calc(
        uint256 balance,
        uint256 units,
        uint256 totalUnits
    ) internal pure returns (uint256) {
        require(totalUnits > 0, "totalUnits must be greater than 0");
        require(
            units <= totalUnits,
            "units must be less than or equal to totalUnits"
        );
        if (balance == 0) {
            return 0;
        }
        // 内部和外部代币的余额限制为 2^64-1（参见 Bank.sol:L411-L421）
        // 最大单元数限制为 2^64-1（见 ...）
        // 最坏的情况是：余额=2^64-1 * 单位=2^64-1，没有溢出。
        // The balance for Internal and External tokens are limited to 2^64-1 (see Bank.sol:L411-L421)
        // The maximum number of units is limited to 2^64-1 (see ...)
        // Worst case cenario is: balance=2^64-1 * units=2^64-1, no overflows.
        uint256 prod = balance * units;
        return prod / totalUnits;
    }
}
