// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../core/DaoRegistry.sol";

interface ISignatures {
    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        bytes32 permissionHash,
        bytes32 signatureHash,
        bytes4 magicValue,
        bytes memory data
    ) external;

    function processProposal(DaoRegistry dao, bytes32 proposalId) external;
}
