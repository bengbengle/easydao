pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/DaoRegistry.sol";

interface IOnboarding {
    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address payable applicant,
        address tokenToMint,
        uint256 tokenAmount,
        bytes memory data
    ) external;

    function processProposal(DaoRegistry dao, bytes32 proposalId)
        external
        payable;
}
