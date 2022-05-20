pragma solidity ^0.8.0;



import "../core/DaoRegistry.sol";
import "../guards/AdapterGuard.sol";
import "./modifiers/Reimbursable.sol";
import "./interfaces/IConfiguration.sol";
import "../adapters/interfaces/IVoting.sol";
import "../helpers/DaoHelper.sol";

contract ConfigurationContract is IConfiguration, AdapterGuard, Reimbursable {
    
    // dao --> proposal Id --> newConfigs ---> config type (0, 1)
    mapping(address => mapping(bytes32 => Configuration[])) private _configurations;

    /**
    * @notice 创建并发起配置提案 
    * @param dao DAO 地址
    * @param proposalId 提案 ID 
    * @param configs 键、类型、数字和地址配置值 
    * @param data 有关融资提案的其他详细信息 
    */

    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        Configuration[] calldata configs,
        bytes calldata data
    ) external override reimbursable(dao) {
        require(configs.length > 0, "missing configs");

        dao.submitProposal(proposalId);

        Configuration[] storage newConfigs = _configurations[address(dao)][proposalId];

        for (uint256 i = 0; i < configs.length; i++) {
            Configuration memory config = configs[i];
            newConfigs.push(
                Configuration({
                    key: config.key,
                    configType: config.configType,
                    numericValue: config.numericValue,
                    addressValue: config.addressValue
                })
            );
        }

        IVoting votingContract = IVoting(dao.getAdapterAddress(DaoHelper.VOTING));

        address sponsoredBy = votingContract.getSenderAddress(
            dao,
            address(this),
            data,
            msg.sender
        );

        dao.sponsorProposal(proposalId, sponsoredBy, address(votingContract));
        votingContract.startNewVotingForProposal(dao, proposalId, data);
    }

    /**
     * @notice 处理配置提案以更新 DAO 状态
     * @param dao DAO 地址
     * @param proposalId The proposal id.
     */
    function processProposal(DaoRegistry dao, bytes32 proposalId)
        external
        override
        reimbursable(dao)
    {
        dao.processProposal(proposalId);

        IVoting votingContract = IVoting(dao.votingAdapter(proposalId));
        require(address(votingContract) != address(0), "adapter not found");
        require(
            votingContract.voteResult(dao, proposalId) == IVoting.VotingState.PASS,
            "proposal did not pass"
        );

        Configuration[] memory configs = _configurations[address(dao)][proposalId];

        for (uint256 i = 0; i < configs.length; i++) {
            Configuration memory config = configs[i];
            if (ConfigType.NUMERIC == config.configType) {
                dao.setConfiguration(config.key, config.numericValue);
            } else if (ConfigType.ADDRESS == config.configType) {
                dao.setAddressConfiguration(config.key, config.addressValue);
            }
        }
    }
}
