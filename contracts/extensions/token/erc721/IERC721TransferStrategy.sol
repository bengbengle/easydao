pragma solidity ^0.8.0;


import "../../../core/DaoRegistry.sol";

/**
 *
 */
interface IERC721TransferStrategy {
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
