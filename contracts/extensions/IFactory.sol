pragma solidity ^0.8.0;
import "../core/DaoRegistry.sol";

// SPDX-License-Identifier: MIT

interface IFactory {
    function getExtensionAddress(address dao) external view returns (address);
}
