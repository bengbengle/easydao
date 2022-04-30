pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT
import "../../../core/DaoRegistry.sol";


/**
 *
 * The ERC20Extension is a contract to give erc20 functionality
 * to the internal token units held by DAO members inside the DAO itself.
 */
interface IERC20TransferStrategy {

    enum AclFlag {
        REGISTER_TRANSFER
    }
    
    enum ApprovalType {
        NONE,
        STANDARD,
        SPECIAL
    }
    
    function evaluateTransfer(
        DaoRegistry dao,
        address tokenAddr,
        address from,
        address to,
        uint256 amount,
        address caller
    ) external view returns (ApprovalType, uint256);
}
