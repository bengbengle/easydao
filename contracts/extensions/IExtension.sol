// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../core/DaoRegistry.sol";



interface IExtension {
    function initialize(DaoRegistry dao, address creator) external;
}
