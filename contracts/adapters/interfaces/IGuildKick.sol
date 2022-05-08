pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/DaoRegistry.sol";

interface IGuildKick {
    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address memberToKick,
        bytes calldata data
    ) external;

    function processProposal(DaoRegistry dao, bytes32 proposalId) external;
}
