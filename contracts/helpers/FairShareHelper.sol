// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library FairShareHelper {
    /**
     * @notice 根据总 unit 和当前 balance 计算 fair unit 数量, balance = units + loot , 返回份额
     * @param balance guild 资金
     * @param units  用户 份额
     * @param totalUnits total 份额
     */
    function calc(
        uint256 balance,
        uint256 units,
        uint256 totalUnits
    ) internal pure returns (uint256) {
        require(totalUnits > 0, "totalUnits must be greater than 0");
        require(units <= totalUnits, "units must be less than or equal to totalUnits");

        if (balance == 0) {
            return 0;
        }

        // 内部和外部代币的余额限制为 2^64-1（参见 Bank.sol:L411-L421） 
        // 最大单元数限制为 2^64-1（见 ...） 
        // 最坏的情况是：余额=2^64-1 * 单位=2^64-1，没有溢出
        // balance * units / totalunits 
        uint256 prod = balance * units;

        return prod / totalUnits;
    }
}
