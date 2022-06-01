import {
  daoAccessFlagsMap,
  bankExtensionAclFlagsMap,
  erc721ExtensionAclFlagsMap,
  erc1155ExtensionAclFlagsMap,
  erc1271ExtensionAclFlagsMap,
  vestingExtensionAclFlagsMap,
  entryBank,
  entryERC20,
  entryERC721,
  entryERC1155,
  entryERC1271,
  entryExecutor,
  entryVesting,
  ACLBuilder,
  SelectedACLs,
} from "../utils/access-control-util";

import { extensionsIdsMap, adaptersIdsMap } from "../utils/dao-ids-util";
import { governanceRoles } from "../utils/governance-util";

// 匹配 DaoArtifacts.sol ArtifactType enum 工件类型
export enum ContractType {
  Core = 0,
  Factory = 1,
  Extension = 2,
  Adapter = 3,
  Util = 4,
  Test = 5,
}

/**
 * 每个合约都包含 部署脚本所需的 不同配置， 此类型可帮助您定义这些配置 
 */
export type ContractConfig = {
  
  /**
   * 合约的 id， 一般是从 dao-ids-util.ts 导入
   */
  id: string;
  
  /**
   * solidity 合约的名称，不是文件名，而是 合约本身
   */
  name: string;
  
  /**
   * 将被命名为 以访问合同的 javascript 变量名称。这对于在部署期间创建的变量很有用，
   * 例如 适配器和扩展。使用此别名，您将能够在测试上下文中访问它，
   * 例如：adapters.<alias> 将返回已部署的合约
   */
  alias?: string;
  
  /**
   * 通向 Solidity 合约的路径
   */
  path: string;
  
  /**
   * 如果为 true，则表示必须部署合约
   */
  enabled: boolean;
  
  /**
   * Optional
   * skip auto deploy true indicates that the contract do need to be
   * automatically deployed during the migration script execution.
   * It is useful to skip the auto deploy for contracts that are not required to launch a DAO, 
   * but that you manually configure them after the DAO is created, but not finalized, 
   * e.g: Offchain Voting.
   
   * 合约在迁移脚本执行期间 会跳过 自动部署 
   * 对于不需要启动 DAO 的合约， 跳过自动部署是很有用的， 但是您可以在创建 DAO 后手动配置它们， DaoState is CREATION, not READY
   * 例如：链下投票
   */
  skipAutoDeploy?: boolean;
  
  /**
   * Solidity 合约的版本
   * 它必须是合约的名称，而不是 .sol 文件的名称
   */
  version: string;
  
  /**
   * 基于 ContractType 枚举的合同类型
   */
  type: ContractType;
  
  /**
   * 在 DAO 中选择授予此合约的访问控制层标志
   */
  acls: SelectedACLs;

  /**
   * Optional
   * 根据所选 ACL 标志计算正确 ACL 值的函数
   */
  buildAclFlag?: ACLBuilder;
  
  /**
   * Optional
   * 合约在部署期间可能需要自定义参数， 在此处声明从 env 读取的所有参数，并传递给 配置/部署 函数 
   * 参数名称必须与部署脚本 2_deploy_contracts.js 中提供的参数匹配
   */
  deploymentArgs?: Array<string>;

  /**
   * Optional
   * 部署合约后要传递给 `configureDao` 调用 的参数集
   */
  daoConfigs?: Array<Array<string>>;
  /**
   * Optional
   * 工厂生成的 extensions Id， 通常你会从 extensionsIdsMap 中导入 
   * 例如： BankFactory 生成合约 BankContract 的实例， 因此 BankFactory 配置需要在此属性中设置 extensionsIdsMap.BANK_EXT 以指示它 生成 银行合约
   */
  generatesExtensionId?: string;

  /**
   * Optional
   * 治理角色属性 指示 在评估来自 DAO 成员 的投票时 需要考虑哪个 DAO 配置。
   * 例如： 配置适配器 将 投票权 限制为 持有特定令牌的 成员， 并且 令牌 是通过 治理角色配置 定义的。
   * 如果会员不持有 that don，则投票 不通过
   */
  governanceRoles?: Record<string, string>;
};

export const contracts: Array<ContractConfig> = [
  /**
   * Test Util Contracts
   */
  {
    id: "ol-token",
    name: "OLToken",
    path: "../../contracts/test/OLToken",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Test,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: ["supplyOLToken"],
  },
  {
    id: "weth",
    name: "WETH",
    path: "../../contracts/helpers/WETH",
    enabled: true,
    skipAutoDeploy: true,
    version: "1.0.0",
    type: ContractType.Test,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: [],
  },
  {
    id: "mock-dao",
    name: "MockDao",
    path: "../../contracts/test/MockDao",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Test,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: "test-token-1",
    name: "TestToken1",
    alias: "testToken1",
    path: "../../contracts/test/TestToken1",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Test,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: ["supplyTestToken1"],
  },
  {
    id: "test-token-2",
    name: "TestToken2",
    alias: "testToken2",
    path: "../../contracts/test/TestToken2",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Test,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: ["supplyTestToken2"],
  },
  {
    id: "test-fairshare-calc",
    name: "TestFairShareCalc",
    path: "../../contracts/test/TestFairShareCalc",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Test,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: "pixel-nft",
    name: "PixelNFT",
    alias: "pixelNFT",
    path: "../../contracts/test/PixelNFT",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Test,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: ["supplyPixelNFT"],
  },
  {
    id: "prox-token",
    name: "ProxTokenContract",
    alias: "proxToken",
    path: "../../contracts/test/ProxTokenContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Test,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: "erc20-minter",
    name: "ERC20MinterContract",
    path: "../../contracts/test/ERC20MinterContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Test,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: "erc1155-test-token",
    name: "ERC1155TestToken",
    alias: "erc1155TestToken",
    path: "../../contracts/test/ERC1155TestToken",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Test,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: ["erc1155TestTokenUri"],
  },

  /**
   * DAO Factories Contracts
   */
  {
    id: "dao-factory",
    name: "DaoFactory",
    alias: "daoFactory",
    path: "../../contracts/core/DaoFactory",
    enabled: true,
    skipAutoDeploy: true,
    version: "1.0.0",
    type: ContractType.Factory,
    acls: {
      dao: [],
      extensions: {},
    },
    generatesExtensionId: "dao-registry",
  },
  {
    id: "dao-registry",
    name: "DaoRegistry",
    path: "../../contracts/core/DaoRegistry",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Core,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: "nft-collection-factory",
    name: "NFTCollectionFactory",
    alias: "erc721ExtFactory",
    path: "../../contracts/extensions/NFTCollectionFactory",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Factory,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: ["daoAddress"],
    generatesExtensionId: extensionsIdsMap.ERC721_EXT,
  },
  {
    id: "bank-factory",
    name: "BankFactory",
    alias: "bankExtFactory",
    path: "../../contracts/extensions/bank/BankFactory",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Factory,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: ["daoAddress", "maxExternalTokens"],
    generatesExtensionId: extensionsIdsMap.BANK_EXT,
  },
  {
    id: "erc20-extension-factory",
    name: "ERC20TokenExtensionFactory",
    alias: "erc20ExtFactory",
    path: "../../contracts/extensions/token/erc20/ERC20TokenExtensionFactory",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Factory,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: [
      "daoAddress",
      "erc20TokenName",
      "erc20TokenAddress",
      "erc20TokenSymbol",
      "erc20TokenDecimals",
    ],
    generatesExtensionId: extensionsIdsMap.ERC20_EXT,
  },{
    id: "erc721-extension-factory",
    name: "ERC721TokenExtensionFactory",
    alias: "ERC721ExtFactory",
    path: "../../contracts/extensions/token/erc721/ERC721TokenExtensionFactory",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Factory,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: [
      "daoAddress",
      "erc20TokenName",
      "erc20TokenAddress",
      "erc20TokenSymbol",
      "erc20TokenDecimals",
    ],
    generatesExtensionId: extensionsIdsMap.ERC20_EXT,
  },
  {
    id: "vesting-extension-factory",
    name: "InternalTokenVestingExtensionFactory",
    alias: "vestingExtFactory",
    path: "../../contracts/extensions/token/erc20/InternalTokenVestingExtensionFactory",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Factory,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: ["daoAddress"],
    generatesExtensionId: extensionsIdsMap.VESTING_EXT,
  },
  {
    id: "erc1271-extension-factory",
    name: "ERC1271ExtensionFactory",
    alias: "erc1271ExtFactory",
    path: "../../contracts/extensions/erc1271/ERC1271ExtensionFactory",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Factory,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: ["daoAddress"],
    generatesExtensionId: extensionsIdsMap.ERC1271_EXT,
  },
  {
    id: "executor-extension-factory",
    name: "ExecutorExtensionFactory",
    alias: "executorExtFactory",
    path: "../../contracts/extensions/executor/ExecutorExtensionFactory",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Factory,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: ["daoAddress"],
    generatesExtensionId: extensionsIdsMap.EXECUTOR_EXT,
  },
  {
    id: "erc1155-extension-factory",
    name: "ERC1155TokenCollectionFactory",
    alias: "erc1155ExtFactory",
    path: "../../contracts/extensions/erc1155/ERC1155TokenCollectionFactory",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Factory,
    acls: {
      dao: [],
      extensions: {},
    },
    deploymentArgs: ["daoAddress"],
    generatesExtensionId: extensionsIdsMap.ERC1155_EXT,
  },

  /**
   * Extensions
   */
  {
    id: extensionsIdsMap.ERC721_EXT,
    name: "NFTExtension",
    alias: "erc721Ext",
    path: "../../contracts/extensions/nft/NFTExtension",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Extension,
    buildAclFlag: entryERC721,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: extensionsIdsMap.BANK_EXT,
    name: "BankExtension",
    alias: "bankExt",
    path: "../../contracts/extensions/bank/BankExtension",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Extension,
    buildAclFlag: entryBank,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: extensionsIdsMap.ERC20_EXT,
    name: "ERC20Extension",
    alias: "erc20Ext",
    path: "../../contracts/extensions/token/erc20/ERC20Extension",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Extension,
    buildAclFlag: entryERC20,
    acls: {
      dao: [daoAccessFlagsMap.NEW_MEMBER],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.INTERNAL_TRANSFER,
        ],
      },
    },
  },
  {
    id: extensionsIdsMap.VESTING_EXT,
    name: "InternalTokenVestingExtension",
    alias: "vestingExt",
    path: "../../contracts/extensions/token/erc20/InternalTokenVestingExtension",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Extension,
    buildAclFlag: entryVesting,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: extensionsIdsMap.ERC1271_EXT,
    name: "ERC1271Extension",
    alias: "erc1271Ext",
    path: "../../contracts/extensions/erc1271/ERC1271Extension",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Extension,
    buildAclFlag: entryERC1271,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: extensionsIdsMap.EXECUTOR_EXT,
    name: "ExecutorExtension",
    alias: "executorExt",
    path: "../../contracts/extensions/executor/ExecutorExtension",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Extension,
    buildAclFlag: entryExecutor,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: extensionsIdsMap.ERC1155_EXT,
    name: "ERC1155TokenExtension",
    alias: "erc1155Ext",
    path: "../../contracts/extensions/erc1155/ERC1155TokenExtension",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Extension,
    buildAclFlag: entryERC1155,
    acls: {
      dao: [],
      extensions: {},
    },
  },

  /**
   * Adapters
   */
  {
    id: adaptersIdsMap.DAO_REGISTRY_ADAPTER,
    name: "DaoRegistryAdapterContract",
    alias: "daoRegistryAdapter",
    path: "../../contracts/adapters/DaoRegistryAdapterContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [daoAccessFlagsMap.UPDATE_DELEGATE_KEY],
      extensions: {},
    },
  },
  {
    id: adaptersIdsMap.BANK_ADAPTER,
    name: "BankAdapterContract",
    alias: "bankAdapter",
    path: "../../contracts/adapters/BankAdapterContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.WITHDRAW,
          bankExtensionAclFlagsMap.SUB_FROM_BALANCE,
          bankExtensionAclFlagsMap.ADD_TO_BALANCE,
          bankExtensionAclFlagsMap.UPDATE_TOKEN,
        ],
      },
    },
  },
  {
    id: adaptersIdsMap.CONFIGURATION_ADAPTER,
    name: "ConfigurationContract",
    alias: "configuration",
    path: "../../contracts/adapters/ConfigurationContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [
        daoAccessFlagsMap.SUBMIT_PROPOSAL,
        daoAccessFlagsMap.SET_CONFIGURATION,
      ],
      extensions: {},
    },
    governanceRoles: {
      [governanceRoles.ONLY_GOVERNOR]: "maintainerTokenAddress",
    },
  },
  {
    id: adaptersIdsMap.ERC1155_ADAPTER,
    name: "ERC1155AdapterContract",
    alias: "erc1155Adapter",
    path: "../../contracts/adapters/ERC1155AdapterContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [],
      extensions: {
        [extensionsIdsMap.ERC721_EXT]: [
          erc721ExtensionAclFlagsMap.COLLECT_NFT,
          erc721ExtensionAclFlagsMap.WITHDRAW_NFT,
          erc721ExtensionAclFlagsMap.INTERNAL_TRANSFER,
        ],
        [extensionsIdsMap.ERC1155_EXT]: [
          erc1155ExtensionAclFlagsMap.COLLECT_NFT,
          erc1155ExtensionAclFlagsMap.WITHDRAW_NFT,
          erc1155ExtensionAclFlagsMap.INTERNAL_TRANSFER,
        ],
      },
    },
  },
  {
    id: adaptersIdsMap.MANAGING_ADAPTER,
    name: "ManagingContract",
    alias: "managing",
    path: "../../contracts/adapters/ManagingContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [
        daoAccessFlagsMap.SUBMIT_PROPOSAL,

        daoAccessFlagsMap.REPLACE_ADAPTER,
        daoAccessFlagsMap.ADD_EXTENSION,
        daoAccessFlagsMap.REMOVE_EXTENSION,
        
        daoAccessFlagsMap.SET_CONFIGURATION,
      ],
      extensions: {},
    },
    governanceRoles: {
      [governanceRoles.ONLY_GOVERNOR]: "maintainerTokenAddress",
    },
  },

  // Signature Adapters
  {
    id: adaptersIdsMap.ERC1271_ADAPTER,
    name: "SignaturesContract",
    alias: "signatures",
    path: "../../contracts/adapters/SignaturesContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [daoAccessFlagsMap.SUBMIT_PROPOSAL],
      extensions: {
        [extensionsIdsMap.ERC1271_EXT]: [erc1271ExtensionAclFlagsMap.SIGN],
      },
    },
  },

  // Voting Adapters
  {
    id: adaptersIdsMap.VOTING_ADAPTER,
    name: "VotingContract",
    alias: "voting",
    path: "../../contracts/adapters/VotingContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [],
      extensions: {},
    },
    daoConfigs: [["daoAddress", "votingPeriod", "gracePeriod"]],
  },
  {
    id: adaptersIdsMap.SNAPSHOT_PROPOSAL_ADAPTER,
    name: "SnapshotProposalContract",
    alias: "snapshotProposalAdapter",
    path: "../../contracts/adapters/voting/SnapshotProposalContract",
    enabled: true,
    skipAutoDeploy: true,
    version: "1.0.0",
    type: ContractType.Util,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: "OffchainVotingHelperContract",
    name: "OffchainVotingHelperContract",
    alias: "offchainVotingHelper",
    path: "../../contracts/helpers/OffchainVotingHelperContract",
    enabled: true,
    skipAutoDeploy: true,
    version: "1.0.0",
    type: ContractType.Util,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: adaptersIdsMap.VOTING_ADAPTER,
    name: "OffchainVotingContract",
    alias: "voting",
    path: "../../contracts/adapters/voting/OffchainVotingContract",
    // Disabled because it is not deployed with all the other contracts
    enabled: true,
    skipAutoDeploy: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.ADD_TO_BALANCE,
          bankExtensionAclFlagsMap.SUB_FROM_BALANCE,
          bankExtensionAclFlagsMap.INTERNAL_TRANSFER,
        ],
      },
    },
  },
  {
    id: adaptersIdsMap.VOTING_HASH_ADAPTER,
    name: "OffchainVotingHashContract",
    alias: "offchainVotingHashAdapter",
    path: "../../contracts/adapters/voting/OffchainVotingHashContract",
    // Disabled because it is not deployed with all the other contracts
    enabled: true,
    skipAutoDeploy: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: adaptersIdsMap.KICK_BAD_REPORTER_ADAPTER,
    name: "KickBadReporterAdapter",
    alias: "kickBadReporterAdapter",
    path: "../../contracts/adapters/voting/KickBadReporterAdapter",
    // Disabled because it is not deployed with all the other contracts
    enabled: true,
    skipAutoDeploy: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [],
      extensions: {},
    },
  },

  // Withdraw / Kick Adapters
  {
    id: adaptersIdsMap.RAGEQUIT_ADAPTER,
    name: "RagequitContract",
    alias: "ragequit",
    path: "../../contracts/adapters/RagequitContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.INTERNAL_TRANSFER,
          bankExtensionAclFlagsMap.SUB_FROM_BALANCE,
          bankExtensionAclFlagsMap.ADD_TO_BALANCE,
        ],
      },
    },
  },
  {
    id: adaptersIdsMap.GUILDKICK_ADAPTER,
    name: "GuildKickContract",
    alias: "guildkick",
    path: "../../contracts/adapters/GuildKickContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [daoAccessFlagsMap.SUBMIT_PROPOSAL],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.INTERNAL_TRANSFER,
          bankExtensionAclFlagsMap.SUB_FROM_BALANCE,
          bankExtensionAclFlagsMap.ADD_TO_BALANCE,
          bankExtensionAclFlagsMap.REGISTER_NEW_TOKEN,
        ],
      },
    },
  },
  {
    id: adaptersIdsMap.DISTRIBUTE_ADAPTER,
    name: "DistributeContract",
    alias: "distribute",
    path: "../../contracts/adapters/DistributeContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [daoAccessFlagsMap.SUBMIT_PROPOSAL],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.INTERNAL_TRANSFER,
        ],
      },
    },
  },

  // Funding/Onboarding Adapters
  {
    id: adaptersIdsMap.FINANCING_ADAPTER,
    name: "FinancingContract",
    alias: "financing",
    path: "../../contracts/adapters/FinancingContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [daoAccessFlagsMap.SUBMIT_PROPOSAL],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.INTERNAL_TRANSFER,
          bankExtensionAclFlagsMap.SUB_FROM_BALANCE,
          bankExtensionAclFlagsMap.ADD_TO_BALANCE,
        ],
      },
    },
  },
  {
    id: adaptersIdsMap.REIMBURSEMENT_ADAPTER,
    name: "ReimbursementContract",
    alias: "reimbursement",
    path: "../../contracts/companion/ReimbursementContract",
    enabled: false,
    version: "1.0.0",
    type: ContractType.Adapter,
    deploymentArgs: ["gelato"],
    acls: {
      dao: [],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.ADD_TO_BALANCE,
          bankExtensionAclFlagsMap.SUB_FROM_BALANCE,
          bankExtensionAclFlagsMap.INTERNAL_TRANSFER,
          bankExtensionAclFlagsMap.WITHDRAW,
        ],
      },
    },
    daoConfigs: [
      //config to mint UNITS
      ["daoAddress", "gasPriceLimit", "spendLimitPeriod", "spendLimitEth"],
    ],
  },
  {
    id: adaptersIdsMap.ONBOARDING_ADAPTER,
    name: "OnboardingContract",
    alias: "onboarding",
    path: "../../contracts/adapters/OnboardingContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [
        daoAccessFlagsMap.SUBMIT_PROPOSAL,
        daoAccessFlagsMap.UPDATE_DELEGATE_KEY,
        daoAccessFlagsMap.NEW_MEMBER,
      ],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.ADD_TO_BALANCE,
          bankExtensionAclFlagsMap.INTERNAL_TRANSFER,
        ],
      },
    },
    daoConfigs: [
      //config to mint UNITS
      [
        "daoAddress",
        "unitTokenToMint",
        "unitPrice",
        "nbUnits",
        "maxChunks",
        "tokenAddr",
      ],
      //config to mint LOOT
      [
        "daoAddress",
        "lootTokenToMint",
        "unitPrice",
        "nbUnits",
        "maxChunks",
        "tokenAddr",
      ],
    ],
  },
  {
    id: adaptersIdsMap.COUPON_ONBOARDING_ADAPTER,
    name: "CouponOnboardingContract",
    alias: "couponOnboarding",
    path: "../../contracts/adapters/CouponOnboardingContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [daoAccessFlagsMap.NEW_MEMBER],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.INTERNAL_TRANSFER,
          bankExtensionAclFlagsMap.ADD_TO_BALANCE,
        ],
      },
    },
    daoConfigs: [
      //config to mint coupons
      [
        "daoAddress",
        "couponCreatorAddress",
        extensionsIdsMap.ERC20_EXT, //loads the address from the ext
        "unitTokenToMint",
        "maxAmount",
      ],
    ],
  },
  {
    id: adaptersIdsMap.KYC_ONBOARDING_ADAPTER,
    name: "KycOnboardingContract",
    alias: "kycOnboarding",
    path: "../../contracts/adapters/KycOnboardingContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    deploymentArgs: ["weth"],
    acls: {
      dao: [daoAccessFlagsMap.NEW_MEMBER],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.INTERNAL_TRANSFER,
          bankExtensionAclFlagsMap.ADD_TO_BALANCE,
        ],
      },
    },
    daoConfigs: [
      [
        "daoAddress",
        "kycSignerAddress",
        "unitPrice",
        "nbUnits",
        "maxChunks",
        "maxUnits",
        "kycMaxMembers",
        "kycFundTargetAddress",
        "tokenAddr",
        "unitTokenToMint",
      ],
    ],
  },
  {
    id: adaptersIdsMap.TRIBUTE_ADAPTER,
    name: "TributeContract",
    alias: "tribute",
    path: "../../contracts/adapters/TributeContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [daoAccessFlagsMap.SUBMIT_PROPOSAL, daoAccessFlagsMap.NEW_MEMBER],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.ADD_TO_BALANCE,
          bankExtensionAclFlagsMap.REGISTER_NEW_TOKEN,
        ],
      },
    },
    daoConfigs: [
      //config to mint UNITS
      ["daoAddress", "unitTokenToMint"],
      //config to mint LOOT
      ["daoAddress", "lootTokenToMint"],
    ],
  },
  {
    id: adaptersIdsMap.TRIBUTE_NFT_ADAPTER,
    name: "TributeNFTContract",
    alias: "tributeNFT",
    path: "../../contracts/adapters/TributeNFTContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [daoAccessFlagsMap.SUBMIT_PROPOSAL, daoAccessFlagsMap.NEW_MEMBER],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [bankExtensionAclFlagsMap.ADD_TO_BALANCE],
        [extensionsIdsMap.ERC721_EXT]: [erc721ExtensionAclFlagsMap.COLLECT_NFT],
      },
    },
    daoConfigs: [
      //config to mint UNITS
      ["daoAddress", "unitTokenToMint"],
    ],
  },
  {
    id: adaptersIdsMap.LEND_NFT_ADAPTER,
    name: "LendNFTContract",
    alias: "lendNFT",
    path: "../../contracts/adapters/LendNFTContract",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [daoAccessFlagsMap.SUBMIT_PROPOSAL, daoAccessFlagsMap.NEW_MEMBER],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.SUB_FROM_BALANCE,
          bankExtensionAclFlagsMap.ADD_TO_BALANCE,
        ],
        [extensionsIdsMap.ERC721_EXT]: [
          erc721ExtensionAclFlagsMap.COLLECT_NFT,
          erc721ExtensionAclFlagsMap.WITHDRAW_NFT,
        ],
        [extensionsIdsMap.ERC1155_EXT]: [
          erc1155ExtensionAclFlagsMap.COLLECT_NFT,
          erc1155ExtensionAclFlagsMap.WITHDRAW_NFT,
        ],
        [extensionsIdsMap.VESTING_EXT]: [
          vestingExtensionAclFlagsMap.NEW_VESTING,
          vestingExtensionAclFlagsMap.REMOVE_VESTING,
        ],
      },
    },
    daoConfigs: [
      //config to mint UNITS
      ["daoAddress", "unitTokenToMint"],
    ],
  },
  {
    id: adaptersIdsMap.ERC20_TRANSFER_STRATEGY_ADAPTER,
    name: "ERC20TransferStrategy",
    alias: "erc20TransferStrategy",
    path: "../../contracts/extensions/token/erc20/ERC20TransferStrategy",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Adapter,
    acls: {
      dao: [],
      extensions: {
        [extensionsIdsMap.BANK_EXT]: [
          bankExtensionAclFlagsMap.INTERNAL_TRANSFER,
        ],
      },
    },
  },

  /**
   * Utils
   */
  {
    id: "dao-artifacts",
    name: "DaoArtifacts",
    path: "../../contracts/utils/DaoArtifacts",
    enabled: true,
    skipAutoDeploy: true,
    version: "1.0.0",
    type: ContractType.Util,
    acls: {
      dao: [],
      extensions: {},
    },
  },
  {
    id: "multicall",
    name: "Multicall",
    path: "../../contracts/utils/Multicall",
    enabled: true,
    version: "1.0.0",
    type: ContractType.Util,
    acls: {
      dao: [],
      extensions: {},
    },
  },
];

export const getConfig = (name: string) => {
  return contracts.find((c) => c.name === name);
};

export const isDeployable = (name: string) => {
  const c = getConfig(name);
  return c && c.enabled;
};
