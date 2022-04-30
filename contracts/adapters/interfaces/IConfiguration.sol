pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../core/DaoRegistry.sol";


interface IConfiguration {
    enum ConfigType {
        NUMERIC,
        ADDRESS
    }

    struct Configuration {
        bytes32 key;
        uint256 numericValue;
        address addressValue;
        ConfigType configType;
    }

    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        Configuration[] calldata configs,
        bytes calldata data
    ) external;

    function processProposal(DaoRegistry dao, bytes32 proposalId) external;
}
