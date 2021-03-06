// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../helpers/DaoHelper.sol";
import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "../extensions/token/erc20/ERC20TokenExtension.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library GovernanceHelper {
    string public constant ROLE_PREFIX = "governance.role.";

    // 默认治理代币
    bytes32 public constant DEFAULT_GOV_TOKEN_CFG = keccak256(abi.encodePacked(ROLE_PREFIX, "default"));

    /*
     * @dev 检查成员地址是否拥有足够的资金被视为 州长  
     * @param dao DAO 地址  
     * @param memberAddr 要验证为州长的 消息发送者  
     * @param proposalId 用于检索治理令牌地址的提案 ID（如果已配置）  
     * @param snapshot 用于检查已配置成员的治理令牌余额的快照 ID 
     */
    function getVotingWeight(
        DaoRegistry dao,
        address voterAddr,
        bytes32 proposalId,
        uint256 snapshot
    ) internal view returns (uint256) {
        (address adapterAddress, ) = dao.proposals(proposalId);

        // 1st - 如果 设置了 自定义的 治理令牌, 返回设置的 令牌 的投票权重 
        bytes32 adapterAddressToken = keccak256(abi.encodePacked(ROLE_PREFIX, adapterAddress));
        address governanceToken = dao.getAddressConfiguration(adapterAddressToken);
        if (DaoHelper.isNotZeroAddress(governanceToken)) {
            return getVotingWeight(dao, governanceToken, voterAddr, snapshot);
        }

        // 2nd - 如果 有 默认的治理令牌， 返回 默认令牌 读取投票权重
        bytes32 defaultGovernanceToken = keccak256(abi.encodePacked(ROLE_PREFIX, "default"));
        governanceToken = dao.getAddressConfiguration(defaultGovernanceToken);
        if (DaoHelper.isNotZeroAddress(governanceToken)) {
            return getVotingWeight(dao, governanceToken, voterAddr, snapshot);
        }

        // 3nd 如果前两项都没设置， 就假设 治理代币是 UNITS， 然后读取基于该代币的投票权重 
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );

        return bank.getPriorAmount(voterAddr, DaoHelper.UNITS, snapshot);
    }

    function getVotingWeight(
        DaoRegistry dao,
        address governanceToken,
        address voterAddr,
        uint256 snapshot
    ) internal view returns (uint256) {
        BankExtension bank = BankExtension(dao.getExtensionAddress(DaoHelper.BANK));

        if (bank.isInternalToken(governanceToken)) {
            return bank.getPriorAmount(voterAddr, governanceToken, snapshot);
        }

        // 外部令牌 必须实现 getPriorAmount ， 否则失败并恢复, revert 捕获错误，返回错误消息  
        try ERC20Extension(governanceToken).getPriorAmount(voterAddr, snapshot)
        returns (uint256 votingWeight) {
            return votingWeight;
        } catch {
            revert("getPriorAmount not implemented");
        }
    }
}
