pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/DaoRegistry.sol";

interface IRagequit {
    function ragequit(
        DaoRegistry dao,
        uint256 unitsToBurn,
        uint256 lootToBurn,
        address[] memory tokens
    ) external;
}
