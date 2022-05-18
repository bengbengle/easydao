pragma solidity ^0.8.0;


import "../helpers/FairShareHelper.sol";

contract TestFairShareCalc {
    function calculate(
        uint256 balance,
        uint256 units,
        uint256 totalUnits
    ) external pure returns (uint256) {
        return FairShareHelper.calc(balance, units, totalUnits);
    }
}
