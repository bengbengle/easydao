pragma solidity ^0.8.0;
import "../core/DaoRegistry.sol";

// SPDX-License-Identifier: MIT

interface IExtension {
    function initialize(DaoRegistry dao, address creator) external;
}
