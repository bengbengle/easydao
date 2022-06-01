// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../core/DaoRegistry.sol";



interface IFactory {
    function getExtensionAddress(address dao) external view returns (address);
}
