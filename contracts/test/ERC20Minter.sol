pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "../extensions/executor/Executor.sol";
import "../helpers/DaoHelper.sol";
import "../guards/AdapterGuard.sol";
import "../adapters/interfaces/IConfiguration.sol";
import "./ProxToken.sol";
import "@openzeppelin/contracts/utils/Address.sol";


contract ERC20MinterContract is AdapterGuard {
    using Address for address payable;

    event Minted(address owner, address token, uint256 amount);

    /**
     * @notice default fallback function to prevent from sending ether to the contract.
     */
    receive() external payable {
        revert("fallback revert");
    }

    function execute(
        DaoRegistry dao,
        address token,
        uint256 amount
    ) external reentrancyGuard(dao) {
        address proxyAddr = dao.getExtensionAddress(DaoHelper.EXECUTOR_EXT);
        ERC20MinterContract executor = ERC20MinterContract(payable(proxyAddr));
        executor.mint(dao, token, amount);
    }

    function mint(
        DaoRegistry dao,
        address token,
        uint256 amount
    ) external executorFunc(dao) {
        address sender = msg.sender;
        ProxTokenContract erc20Token = ProxTokenContract(token);
        erc20Token.mint(amount);
        emit Minted(sender, token, amount);
    }
}
