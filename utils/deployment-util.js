// Whole-script strict mode syntax
"use strict";

const { entryDao, entryBank } = require("./access-control-util");
const { adaptersIdsMap, extensionsIdsMap } = require("./dao-ids-util");
const { UNITS, LOOT, ZERO_ADDRESS, sha3, embedConfigs, encodePacked, getAddress, waitTx, } = require("./contract-util.js");
const { debug, info, error } = require("./log-util");
const { ContractType } = require("../configs/contracts.config");

/**
 * 根据 config 参数中定义的合约名称部署合约， 如果在选项对象中找不到合约，则部署将返回并出现错误 
 */
const deployContract = ({ config, options }) => {
  const contract = options[config.name];
  if (!contract)
    throw new Error(`Contract ${config.name} not found in environment options`);

  if (config.deploymentArgs && config.deploymentArgs.length > 0) {
    const args = config.deploymentArgs.map((argName) => {
      const arg = options[argName];
      if (arg !== null && arg !== undefined) return arg;
      throw new Error(
        `Missing deployment argument <${argName}> for ${config.name}`
      );
    });
    return options.deployFunction(contract, args);
  }
  return options.deployFunction(contract);
};

/**
 * 部署使用 Factory 类型定义的所有合约  
 * 合约必须在 configs/networks/.config.ts 中启用， 并且不应在自动部署过程中跳过  
 * 工厂合约必须在 options 对象中提供  
 * 如果在 options 对象中找不到合约，则部署将返回并出现错误 
 */
const createFactories = async ({ options }) => {
  const factories = {};
  const factoryList = Object.values(options.contractConfigs)
    .filter((config) => config.type === ContractType.Factory)
    .filter((config) => config.enabled)
    .filter((config) => !config.skipAutoDeploy);

  debug("deploying or reusing ", factoryList.length, " factories...");
  await factoryList.reduce((p, config) => {
    return p.then((_) => {
      const factoryContract = options[config.name];
      if (!factoryContract)
        throw new Error(`Missing factory contract ${config.name}`);

      const extensionConfig = options.contractConfigs.find(
        (c) => c.id === config.generatesExtensionId
      );
      if (!extensionConfig)
        throw new Error(
          `Missing extension config ${config.generatesExtensionId}`
        );

      const extensionContract = options[extensionConfig.name];
      if (!extensionContract)
        throw new Error(`Missing extension contract ${extensionConfig.name}`);

      return options
        .deployFunction(factoryContract, [extensionContract])
        .then((factory) => (factories[factory.configs.alias] = factory))
        .catch((err) => {
          error(`Failed factory deployment [${config.name}]. `, err);
          throw err;
        });
    });
  }, Promise.resolve());

  return factories;
};

/**
 * 为了部署 Extensions ，它使用每个 Extensions 的工厂合约， 所以必须首先部署工厂 
 */
const createExtensions = async ({ dao, factories, options }) => {
  const extensions = {};
  debug("create extensions ...");
  const createExtension = async ({ dao, factory, options }) => {
    debug("create extension ", factory.configs.alias);
    const factoryConfigs = factory.configs;
    const extensionConfigs = options.contractConfigs.find(
      (c) => c.id === factoryConfigs.generatesExtensionId
    );
    if (!extensionConfigs)
      throw new Error(`Missing extension configuration <generatesExtensionId> for in ${factoryConfigs.name} configs`);

    if (factoryConfigs.deploymentArgs && factoryConfigs.deploymentArgs.length > 0) {

      const args = factoryConfigs.deploymentArgs.map((argName) => {
        const arg = options[argName];
        if (arg !== null && arg !== undefined) return arg;
        throw new Error(
          `Missing deployment argument <${argName}> in ${factoryConfigs.name}.create`
        );
      });
      await waitTx(factory.create(...args));
    } else {
      await waitTx(factory.create());
    }

    const extensionInterface = options[extensionConfigs.name];
    if (!extensionInterface)
      throw new Error(`Extension contract not found for ${extensionConfigs.name}`);

    const extensionAddress = await factory.getExtensionAddress(options.daoAddress);

    const newExtension = embedConfigs(
      await options.attachFunction(extensionInterface, extensionAddress),
      extensionInterface.contractName,
      options.contractConfigs
    );

    if (!newExtension || !newExtension.configs)
      throw new Error(
        `Unable to embed extension configs for ${extensionConfigs.name}`
      );

    await waitTx(
      dao.addExtension(
        sha3(newExtension.configs.id),
        newExtension.address,
        options.owner
      )
    );

    info(`
    Extension enabled '${newExtension.configs.name}'
    -------------------------------------------------
     contract address: ${newExtension.address}
     creator address:  ${options.owner}`);

    return newExtension;
  };

  await Object.values(factories).reduce(
    (p, factory) =>
      p
        .then(() =>
          createExtension({
            dao,
            factory,
            options,
          })
        )
        .then((ext) => (extensions[ext.configs.alias] = ext))
        .catch((err) => {
          error(`Failed extension deployment ${factory.configs.name}. `, err);
          throw err;
        }),
    Promise.resolve()
  );
  return extensions;
};

/** 
 * 部署所有使用适配器类型定义的合约。 
 * 合约必须在 configs/networks/*.config.ts 中启用， 并且不应在自动部署过程中跳过。 
 * 适配器合约必须在选项对象中提供。 
 * 如果在选项对象中找不到合约，则部署将返回并出现错误。 */
const createAdapters = async ({ options }) => {
  const adapters = {};
  const adapterList = Object.values(options.contractConfigs)
    .filter((config) => config.type === ContractType.Adapter)
    .filter((config) => config.enabled)
    .filter((config) => !config.skipAutoDeploy);

  debug("deploying or re-using ", adapterList.length, " adapters...");
  await adapterList.reduce(
    (p, config) =>
      p
        .then(() => deployContract({ config, options }))
        .then((adapter) => (adapters[adapter.configs.alias] = adapter))
        .catch((err) => {
          error(`Error while creating adapter ${config.name}. `, err);
          throw err;
        }),
    Promise.resolve()
  );

  return adapters;
};

/**
 * 部署使用 Util 类型定义的所有实用程序合同
 * 合约必须在 configs/networks/*.config.ts 中启用， 并且不应在自动部署过程中跳过
 * util 合约必须在 options 对象中提供
 * 如果在选项对象中找不到合约，则部署将返回并出现错误
*/
const createUtilContracts = async ({ options }) => {
  const utilContracts = {};

  await Object.values(options.contractConfigs)
    .filter((config) => config.type === ContractType.Util)
    .filter((config) => config.enabled)
    .filter((config) => !config.skipAutoDeploy)
    .reduce(
      (p, config) =>
        p
          .then(() => deployContract({ config, options }))
          .then(
            (utilContract) =>
              (utilContracts[utilContract.configs.alias] = utilContract)
          )
          .catch((err) => {
            error(`Error while creating util contract ${config.name}. `, err);
            throw err;
          }),
      Promise.resolve()
    );
  return utilContracts;
};

/** 
 * 如果选项中启用了标志 `deployTestTokens`，则部署所有使用测试类型定义的测试合约。合约必须在 configs/networks/*.config.ts 中启用， 并且不应在自动部署过程中跳过
 * 测试合约必须在选项对象中提供
 * 如果在选项对象中找不到合约，则部署将返回并出现错误
 */
const createTestContracts = async ({ options }) => {
  const testContracts = {};

  if (!options.deployTestTokens) return testContracts;

  await Object.values(options.contractConfigs)
    .filter((config) => config.type === ContractType.Test)
    .filter((config) => config.enabled)
    .filter((config) => !config.skipAutoDeploy)
    .reduce(
      (p, config) =>
        p
          .then(() => deployContract({ config, options }))
          .then(
            (testContract) =>
              (testContracts[testContract.configs.alias] = testContract)
          )
          .catch((err) => {
            error(`Error while creating test contract ${config.name}. `, err);
            throw err;
          }),
      Promise.resolve()
    );
  return testContracts;
};

/**
 * 根据合约 configs.governanceRoles 在 DAO Registry 中创建治理配置角色
 */
const createGovernanceRoles = async ({ options, dao, adapters }) => {
  const readConfigValue = (configName, contractName) => {
    const configValue = options[configName];
    if (!configValue)
      throw new Error(
        `Error while creating governance role [${configName}] for ${contractName}`
      );
    return configValue;
  };

  await Object.values(options.contractConfigs)
    .filter((c) => c.enabled)
    .filter((c) => c.governanceRoles)
    .reduce((p, c) => {
      const roles = Object.keys(c.governanceRoles);
      return p.then(() =>
        roles.reduce(
          (q, role) =>
            q.then(async () => {
              const adapter = Object.values(adapters).find(
                (a) => a.configs.name === c.name
              );
              const configKey = sha3(
                encodePacked(
                  role.replace("$contractAddress", ""),
                  getAddress(adapter.address)
                )
              );
              const configValue = getAddress(
                readConfigValue(c.governanceRoles[role], c.name)
              );
              console.log('configKey:', configKey, 'configValue:', configValue);
              return await waitTx(
                dao.setAddressConfiguration(configKey, configValue)
              );
            }),
          Promise.resolve()
        )
      );
    }, Promise.resolve());

  if (options.defaultMemberGovernanceToken) {
    const configKey = sha3(encodePacked("governance.role.default"));
    await waitTx(
      dao.setAddressConfiguration(configKey,
        getAddress(options.defaultMemberGovernanceToken)
      )
    );
  }
};

const validateContractConfigs = (contractConfigs) => {
  if (!contractConfigs) throw Error(`Missing contract configs`);

  const found = new Map();
  Object.values(contractConfigs)
    .filter(
      (c) =>
        c.type === ContractType.Adapter &&
        c.id !== adaptersIdsMap.VOTING_ADAPTER
    )
    .forEach((c) => {
      const current = found.get(c.id);
      if (current) {
        throw Error(`Duplicate contract Id detected: ${c.id}`);
      }
      found.set(c.id, true);
    });
};

/**
 * 部署 configs/contracts.config.ts 中定义的所有合约  
 * 合约必须在 configs/networks/.config.ts 中启用， 并且不应在自动部署过程中跳过  
 * 每一份合约都必须在 options 对象中提供  
 * 如果在 options 对象中找不到合约，则部署将返回并出现错误 
 * 它还为 DAO 配置正确的访问权限，并为所有适配器和扩展配置参数 
 *
 *   
 * 仅当通过 options.offchainVoting 参数需要时才部署链下投票 
 *
 * 所有已部署的合约都将在映射中返回， 其中别名在 ​​configs/networks/.config.ts 中定义 
 */
const deployDao = async (options) => {
  validateContractConfigs(options.contractConfigs);

  const { dao, daoFactory } = await cloneDao({...options, name: options.daoName || "test-dao"});

  options = {
    ...options,
    daoAddress: dao.address,
    unitTokenToMint: UNITS,
    lootTokenToMint: LOOT,
  };

  const factories = await createFactories({ options });
  const extensions = await createExtensions({ dao, factories, options });
  const adapters = await createAdapters({ dao, daoFactory, extensions, options });

  await createGovernanceRoles({ options, dao, adapters });

  await configureDao({owner: options.owner, dao, daoFactory, extensions, adapters, options});

  const votingHelpers = await configureOffchainVoting({ ...options, dao, daoFactory, extensions});

  // 如果创建了链下合约， 则使用别名将其设置为 适配器 映射
  if (votingHelpers.offchainVoting) {
    
    adapters[votingHelpers.offchainVoting.configs.alias] = votingHelpers.offchainVoting;
  }

  // 部署 utility 合同
  const utilContracts = await createUtilContracts({ options });

  // 部署 测试代币 合约以方便测试
  const testContracts = await createTestContracts({ options });

  if (options.finalize) {
    await waitTx(dao.finalizeDao());
  }

  return {
    dao: dao,
    adapters: adapters,
    extensions: extensions,
    testContracts: testContracts,
    utilContracts: utilContracts,
    votingHelpers: votingHelpers,
    factories: { ...factories, daoFactory },
    owner: options.owner,
  };
};

/**
 * 创建基于 DaoFactory 合约的 DAO 实例 
 * 返回新的 DAO 实例和 dao 名称
 */
const cloneDao = async ({
  owner,
  creator,
  deployFunction,
  attachFunction,
  DaoRegistry,
  DaoFactory,
  name,
}) => {

  const daoFactory = await deployFunction(DaoFactory, [DaoRegistry]);
  await waitTx(daoFactory.createDao(name, creator ? creator : owner));

  const daoAddress = await daoFactory.getDaoAddress(name);
  if (daoAddress === ZERO_ADDRESS) throw Error("Invalid dao address");
  
  const daoInstance = await attachFunction(DaoRegistry, daoAddress);
  return { dao: daoInstance, daoFactory, daoName: name };

};

/**
 * 配置 DAO 的实例以使用提供的工厂、扩展和适配器
 * 它确保每个扩展和适配器都启用了正确的 ACL 标志，以便能够与 DAO 实例进行通信， 适配器可以与 DAO 注册表、不同的扩展甚至其他适配器进行通信
 * 扩展可以与 DAO 注册表、其他扩展和适配器进行通信
 */
const configureDao = async ({
  dao,
  daoFactory,
  extensions,
  adapters,
  options,
}) => {
  debug("configure new dao ...");
  const configureAdaptersWithDAOAccess = async () => {
    debug("configure adapters with access");

    // 如果适配器需要访问 DAO 注册表或任何启用的扩展，则需要将其添加到具有正确 ACL 标志的 DAO
    const adaptersWithAccess = Object.values(adapters)
      .filter((a) => a.configs.enabled)
      .filter((a) => !a.configs.skipAutoDeploy)
      .filter((a) => a.configs.acls.dao);

    await adaptersWithAccess.reduce((p, a) => {
      info(`
        Adapter configured '${a.configs.name}'
        -------------------------------------------------
         contract address: ${a.address}
         contract acls: ${JSON.stringify(a.configs.acls)}`);

      return p.then(
        async () =>
          await waitTx(
            daoFactory.addAdapters(dao.address, [
              entryDao(a.configs.id, a.address, a.configs.acls),
            ])
          )
      );
    }, Promise.resolve());

    // 如果一个扩展需要访问其他扩展， 该扩展需要作为适配器合约添加到 DAO， 但没有启用任何 ACL 标志
    const extensionsWithAccess = Object.values(extensions)
      .filter((e) => e.configs.enabled)
      .filter((a) => !a.configs.skipAutoDeploy)
      .filter((e) => Object.keys(e.configs.acls.extensions).length > 0);

    await extensionsWithAccess.reduce((p, e) => {
      info(`
        Extension configured '${e.configs.name}'
        -------------------------------------------------
         contract address: ${e.address}
         contract acls: ${JSON.stringify(e.configs.acls)}`);

      return p.then(
        async () =>
          await waitTx(
            daoFactory.addAdapters(dao.address, [
              entryDao(e.configs.id, e.address, e.configs.acls),
            ])
          )
      );
    }, Promise.resolve());
  };

  const configureAdaptersWithDAOParameters = async () => {
    debug("configure adapters ...");
    const readConfigValue = (configName, contractName) => {
      // 1st check for configs that are using extension addresses
      if (Object.values(extensionsIdsMap).includes(configName)) {
        const extension = Object.values(extensions).find(
          (e) => e.configs.id === configName
        );
        if (!extension || !extension.address)
          throw new Error(
            `Error while configuring dao parameter [${configName}] for ${contractName}. Extension not found.`
          );
        return extension.address;
      }
      // 2nd lookup for configs in the options object
      const configValue = options[configName];
      if (!configValue)
        throw new Error(
          `Error while configuring dao parameter [${configName}] for ${contractName}. Config not found.`
        );
      return configValue;
    };

    const adapterList = Object.values(adapters)
      .filter((a) => a.configs.enabled)
      .filter((a) => !a.configs.skipAutoDeploy)
      .filter((a) => a.configs.daoConfigs && a.configs.daoConfigs.length > 0);

    await adapterList.reduce(async (p, adapter) => {
      const contractConfigs = adapter.configs;
      return await p.then(() =>
        contractConfigs.daoConfigs.reduce(
          (q, configEntry) =>
            q.then(async () => {
              const configValues = configEntry.map((configName) =>
                readConfigValue(configName, contractConfigs.name)
              );
              const p = adapter.configureDao(...configValues).catch((err) => {
                error(
                  `Error while configuring dao with contract ${contractConfigs.name}. `,
                  err
                );
                throw err;
              });
              return await waitTx(p);
            }),
          Promise.resolve()
        )
      );
    }, Promise.resolve());
  };

  const configureExtensionAccess = async (contracts, extension) => {
    debug("configure extension access for ", extension.configs.alias);
    const withAccess = Object.values(contracts).reduce((accessRequired, c) => {
      const configs = c.configs;
      accessRequired.push(
        extension.configs.buildAclFlag(c.address, configs.acls)
      );
      return accessRequired;
    }, []);

    if (withAccess.length > 0)
      await waitTx(
        daoFactory.configureExtension(
          dao.address,
          extension.address,
          withAccess
        )
      );
  };

  /**
   * 配置所有需要访问 DAO 的适配器和每个启用的扩展
   */
  const configureAdapters = async () => {
    debug("configure adapters ...");
    await configureAdaptersWithDAOAccess();
    await configureAdaptersWithDAOParameters();
    const extensionsList = Object.values(extensions)
      .filter((targetExtension) => targetExtension.configs.enabled)
      .filter((targetExtension) => !targetExtension.configs.skipAutoDeploy);

    await extensionsList.reduce((p, targetExtension) => {
      // 过滤可以访问 targetExtension 的已启用适配器
      const contracts = Object.values(adapters)
        .filter((a) => a.configs.enabled)
        .filter((a) => !a.configs.skipAutoDeploy)
        .filter((a) =>
          // 适配器必须至少定义 1 个 ACL 标志才能访问 targetExtension
          Object.keys(a.configs.acls.extensions).some(
            (extId) => extId === targetExtension.configs.id
          )
        );

      return p
        .then(() => configureExtensionAccess(contracts, targetExtension))
        .catch((err) => {
          error(
            `Error while configuring adapters access to extension ${targetExtension.configs.name}. `,
            err
          );
          throw err;
        });
    }, Promise.resolve());
  };

  /**
   * 配置所有需要访问 其他启用的扩展的扩展
   */
  const configureExtensions = async () => {
    debug("configure extensions ...");
    const extensionsList = Object.values(extensions).filter(
      (targetExtension) => targetExtension.configs.enabled
    );

    await extensionsList.reduce((p, targetExtension) => {
      // Filters the enabled extensions that have access to the targetExtension
      const contracts = Object.values(extensions)
        .filter((e) => e.configs.enabled)
        .filter((e) => e.configs.id !== targetExtension.configs.id)
        .filter((e) =>
          // The other extensions must have at least 1 ACL flag defined to access the targetExtension
          Object.keys(e.configs.acls.extensions).some(
            (extId) => extId === targetExtension.configs.id
          )
        );

      return p
        .then(() => configureExtensionAccess(contracts, targetExtension))
        .catch((err) => {
          error(
            `Error while configuring extensions access to extension ${targetExtension.configs.name}. `
          );
          throw err;
        });
    }, Promise.resolve());
  };

  await configureAdapters();
  await configureExtensions();
};

/**
 * 如果启用了标志 `flag options.offchainVoting`，会部署和配置 启用 Offchain 投票适配器 所需的所有合约
 */
const configureOffchainVoting = async ({
  dao,
  daoFactory,
  offchainVoting,
  offchainAdmin,
  votingPeriod,
  gracePeriod,
  SnapshotProposalContract,
  KickBadReporterAdapter,
  OffchainVotingContract,
  OffchainVotingHashContract,
  OffchainVotingHelperContract,
  deployFunction,
  extensions,
}) => {
  debug("configuring offchain voting...");
  const votingHelpers = {
    snapshotProposalContract: null,
    handleBadReporterAdapter: null,
    offchainVoting: null,
  };

  // 链下投票 被禁用
  if (!offchainVoting) return votingHelpers;

  const currentVotingAdapterAddress = await dao.getAdapterAddress(
    sha3(adaptersIdsMap.VOTING_ADAPTER)
  );

  const snapshotProposalContract = await deployFunction(
    SnapshotProposalContract
  );

  const offchainVotingHashContract = await deployFunction(
    OffchainVotingHashContract,
    [snapshotProposalContract.address]
  );

  const offchainVotingHelper = await deployFunction(
    OffchainVotingHelperContract,
    [offchainVotingHashContract.address]
  );

  const handleBadReporterAdapter = await deployFunction(KickBadReporterAdapter);
  const offchainVotingContract = await deployFunction(OffchainVotingContract, [
    currentVotingAdapterAddress,
    offchainVotingHashContract.address,
    offchainVotingHelper.address,
    snapshotProposalContract.address,
    handleBadReporterAdapter.address,
    offchainAdmin,
  ]);

  await waitTx(
    daoFactory.updateAdapter(
      dao.address,
      entryDao(
        offchainVotingContract.configs.id,
        offchainVotingContract.address,
        offchainVotingContract.configs.acls
      )
    )
  );

  await waitTx(
    dao.setAclToExtensionForAdapter(
      extensions.bankExt.address,
      offchainVotingContract.address,
      entryBank(
        offchainVotingContract.address,
        offchainVotingContract.configs.acls
      ).flags
    )
  );

  await waitTx(
    offchainVotingContract.configureDao(
      dao.address,
      votingPeriod,
      gracePeriod,
      10
    )
  );

  votingHelpers.offchainVoting = offchainVotingContract;
  votingHelpers.handleBadReporterAdapter = handleBadReporterAdapter;
  votingHelpers.snapshotProposalContract = snapshotProposalContract;

  return votingHelpers;
};

module.exports = {
  createFactories,
  createExtensions,
  createAdapters,
  deployDao,
  cloneDao,
};
