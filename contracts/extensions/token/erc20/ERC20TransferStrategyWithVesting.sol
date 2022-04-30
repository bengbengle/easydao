pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT
import "../../../core/DaoRegistry.sol";
import "../../../helpers/DaoHelper.sol";
import "../../bank/Bank.sol";
import "./IERC20TransferStrategy.sol";
import "./InternalTokenVestingExtension.sol";


/**
 *
 * The ERC20Extension is a contract to give erc20 functionality
 * to the internal token units held by DAO members inside the DAO itself.
 */
contract ERC20TransferStrategy is IERC20TransferStrategy {
    bytes32 public constant ERC20_EXT_TRANSFER_TYPE =
        keccak256("erc20.transfer.type");

    /// @notice Clonable contract must have an empty constructor
    // constructor() {}

    function hasBankAccess(DaoRegistry dao, address caller)
        public
        view
        returns (bool)
    {
        return
            dao.hasAdapterAccessToExtension(
                caller,
                dao.getExtensionAddress(DaoHelper.BANK),
                uint8(BankExtension.AclFlag.INTERNAL_TRANSFER)
            );
    }

    function evaluateTransfer(
        DaoRegistry dao,
        address tokenAddr,
        address from,
        address to,
        uint256 amount,
        address caller
    ) external view override returns (ApprovalType, uint256) {
        //if the transfer is an internal transfer, then make it unlimited
        if (hasBankAccess(dao, caller)) {
            return (ApprovalType.SPECIAL, amount);
        }

        uint256 transferType = dao.getConfiguration(ERC20_EXT_TRANSFER_TYPE);
        // member only
        if (transferType == 0 && dao.isMember(to)) {
            // members only transfer
            return (
                ApprovalType.STANDARD,
                evaluateStandardTransfer(dao, from, tokenAddr)
            );
            // open transfer
        } else if (transferType == 1) {
            return (
                ApprovalType.STANDARD,
                evaluateStandardTransfer(dao, from, tokenAddr)
            );
        }
        //transfer not allowed
        return (ApprovalType.NONE, 0);
    }

    function evaluateStandardTransfer(
        DaoRegistry dao,
        address from,
        address tokenAddr
    ) public view returns (uint160) {
        InternalTokenVestingExtension vesting = InternalTokenVestingExtension(
            dao.getExtensionAddress(DaoHelper.INTERNAL_TOKEN_VESTING_EXT)
        );
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );

        uint88 minBalance = vesting.getMinimumBalance(from, tokenAddr);
        uint160 balance = bank.balanceOf(from, tokenAddr);

        if (minBalance > balance) {
            return 0;
        }

        return uint160(balance - minBalance);
    }
}
