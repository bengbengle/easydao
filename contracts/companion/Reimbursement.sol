pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "./interfaces/IReimbursement.sol";
import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "../guards/AdapterGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../helpers/DaoHelper.sol";
import "./GelatoRelay.sol";

contract ReimbursementContract is IReimbursement, AdapterGuard, GelatoRelay {
    using Address for address payable;
    using SafeERC20 for IERC20;

    struct ReimbursementData {
        uint256 ethUsed;
        uint256 rateLimitStart;
    }

    constructor(address payable _gelato) GelatoRelay(_gelato) {}

    mapping(address => ReimbursementData) private _data;

    bytes32 internal constant GasPriceLimit = keccak256("reimbursement.gasPriceLimit");
    bytes32 internal constant SpendLimitPeriod = keccak256("reimbursement.spendLimitPeriod");
    bytes32 internal constant SpendLimitEth = keccak256("reimbursement.spendLimitEth");
    bytes32 internal constant EthUsed = keccak256("reimbursement.ethUsed");
    bytes32 internal constant RateLimitStart = keccak256("reimbursement.rateLimitStart");

    /**
      * @param dao 要配置的 dao 
      * @param gasPriceLimit 允许报销的最高 gas 价格。这用于避免 有人通过设置疯狂的 gas 价格来消耗 DAO 
      * @param spendLimitPeriod 多少​​秒构成一个周期（一种将周期定义为 1 天、1 周、1 小时等的方法...） 
      * @param spendLimitEth 如何在付款期间 可以偿还很多 ETH
    **/
    function configureDao(DaoRegistry dao, uint256 gasPriceLimit, uint256 spendLimitPeriod, uint256 spendLimitEth) 
        external 
        onlyAdapter(dao) 
    {
        require(gasPriceLimit > 0, "gasPriceLimit::invalid");
        require(spendLimitPeriod > 0, "spendLimitPeriod::invalid");
        require(spendLimitEth > 0, "spendLimitEth::invalid");

        dao.setConfiguration(GasPriceLimit, gasPriceLimit);
        dao.setConfiguration(SpendLimitPeriod, spendLimitPeriod);
        dao.setConfiguration(SpendLimitEth, spendLimitEth);
    }

    /**
      * @notice 返回当前交易是否应报销。它返回 spendLimitPeriod 以避免有人在执行期间对其进行更新。 
      * @param dao 要检查的 dao 
      * @param gasLeft 这笔交易中可用的最大 gas
      */
    function shouldReimburse(DaoRegistry dao, uint256 gasLeft)
        external
        view
        override
        returns (bool, uint256)
    {
        // if it is a gelato call, do nothing as it will be handled somewhere else
        if (msg.sender == address(this)) {
            return (false, 0);
        }

        uint256 gasPriceLimit = dao.getConfiguration(GasPriceLimit);

        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );

        if (gasPriceLimit < tx.gasprice) {
            return (false, 0);
        }

        if (bank.balanceOf(DaoHelper.GUILD, DaoHelper.ETH_TOKEN) < gasLeft) {
            return (false, 0);
        }

        uint256 spendLimitPeriod = dao.getConfiguration(SpendLimitPeriod);
        uint256 spendLimitEth = dao.getConfiguration(SpendLimitEth);

        uint256 payback = gasLeft * tx.gasprice;

        if (
            block.timestamp - _data[address(dao)].rateLimitStart <
            spendLimitPeriod
        ) {
            if (spendLimitEth < _data[address(dao)].ethUsed + payback) {
                return (false, 0);
            }
        } else {
            if (spendLimitEth < payback) {
                return (false, 0);
            }
        }

        return (true, spendLimitPeriod);
    }

    /**
     * @notice 报销交易 
     * @param dao 需要报销的 dao 
     * @param caller 谁是调用者（应该报销的人） 
     * @param gasUsage 已经使用了多少 gas 
     * @param spendLimitPeriod 花费限制期执行事务前读取的参数     
     */
    function reimburseTransaction(
        DaoRegistry dao,
        address payable caller,
        uint256 gasUsage,
        uint256 spendLimitPeriod
    ) external override onlyAdapter(dao) {
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        uint256 payback = gasUsage * tx.gasprice;
        if (
            //
            block.timestamp - _data[address(dao)].rateLimitStart < spendLimitPeriod
        ) {
            _data[address(dao)].ethUsed = _data[address(dao)].ethUsed + payback;
        } else {
            _data[address(dao)].rateLimitStart = block.timestamp;
            _data[address(dao)].ethUsed = payback;
        }
        try bank.supportsInterface(bank.withdrawTo.selector) returns (
            bool supportsInterface
        ) {
            if (supportsInterface) {
                bank.withdrawTo(
                    dao,
                    DaoHelper.GUILD,
                    caller,
                    DaoHelper.ETH_TOKEN,
                    payback
                );
            } else {
                bank.internalTransfer(
                    dao,
                    DaoHelper.GUILD,
                    caller,
                    DaoHelper.ETH_TOKEN,
                    payback
                );
                bank.withdraw(dao, caller, DaoHelper.ETH_TOKEN, payback);
            }
        } catch {
            //if supportsInterface reverts ( function does not exist, assume it does not have withdrawTo )
            bank.internalTransfer(
                dao,
                DaoHelper.GUILD,
                caller,
                DaoHelper.ETH_TOKEN,
                payback
            );
            bank.withdraw(dao, caller, DaoHelper.ETH_TOKEN, payback);
        }
    }
}
