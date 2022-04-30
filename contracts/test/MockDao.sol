pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT


contract MockDao {
    enum DaoState {
        CREATION,
        READY
    }

    DaoState public state = DaoState.CREATION;

    function hasAdapterAccessToExtension(
        address,
        address,
        uint8
    ) external pure returns (bool) {
        return true;
    }

    function isMember(address) external pure returns (bool) {
        return true;
    }
}
