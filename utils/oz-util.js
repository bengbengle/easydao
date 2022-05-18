// Whole-script strict mode syntax
"use strict";

const {web3, contract, accounts, provider } = require("@openzeppelin/test-environment");

const chai = require("chai");
const { solidity } = require("ethereum-waffle");
chai.use(solidity);

const { expect } = require("chai");
const { expectRevert } = require("@openzeppelin/test-helpers");
const { deployDao } = require("./deployment-util.js");
const { contracts: allContractConfigs } = require("../configs/networks/test.config");
const { ContractType } = require("../configs/contracts.config");
const { unitPrice, numberOfUnits, maximumChunks, maxAmount, maxUnits, ETH_TOKEN, UNITS, toBN } = require("./contract-util.js");


const getBalance = async (account) => {
  const balance = await web3.eth.getBalance(account);
  return toBN(balance);
};

const attach = async (contractInterface, address) => {
  return await contractInterface.at(address);
};

const deployFunction = async (contractInterface, args, from) => {
  if (!contractInterface) throw Error("undefined contractInterface");

  const contractConfig = allContractConfigs.find(
    (c) => c.name === contractInterface.contractName
  );

  const f = from ? from : accounts[0];
  let instance;
  if (contractConfig.type === ContractType.Factory && args) {
    const identityInterface = args[0];
    const identityInstance = await identityInterface.new();
    const constructorArgs = [identityInstance.address].concat(args.slice(1));
    instance = await contractInterface.new(...constructorArgs, { from: f });
  } else {
    if (args) {
      instance = await contractInterface.new(...args, { from: f });
    } else {
      instance = await contractInterface.new({ from: f });
    }
  }
  return { ...instance, configs: contractConfig };
};

const getContractFromOpenZeppelin = (c) => {
  return contract.fromArtifact(c.substring(c.lastIndexOf("/") + 1));
};

const getOpenZeppelinContracts = (contracts) => {
  return contracts
    .filter((c) => c.enabled)
    .reduce((previousValue, contract) => {
      previousValue[contract.name] = getContractFromOpenZeppelin(contract.path);
      previousValue[contract.name].contractName = contract.name;
      return previousValue;
    }, {});
};

const getDefaultOptions = (options) => {
  return {
    unitPrice: unitPrice,
    nbUnits: numberOfUnits,
    
    votingPeriod: 10,
    gracePeriod: 1,
    
    tokenAddr: ETH_TOKEN,
    maxChunks: maximumChunks,
    maxAmount,
    maxUnits,

    chainId: 1,
    maxExternalTokens: 100,
    couponCreatorAddress: "0x7D8cad0bbD68deb352C33e80fccd4D8e88b4aBb8",
    
    kycMaxMembers: 1000,
    kycSignerAddress: "0x7D8cad0bbD68deb352C33e80fccd4D8e88b4aBb8",
    kycFundTargetAddress: "0x823A19521A76f80EC49670BE32950900E8Cd0ED3",
    
    deployTestTokens: true,
    
    erc20TokenName: "Test Token",
    erc20TokenSymbol: "TTK",
    erc20TokenDecimals: Number(0),
    erc20TokenAddress: UNITS,
    
    supplyTestToken1: 1000000,
    supplyTestToken2: 1000000,
    supplyPixelNFT: 100,
    supplyOLToken: toBN("1000000000000000000000000"),
    erc1155TestTokenUri: "1155 test token",
    
    maintainerTokenAddress: UNITS,
    finalize: options.finalize === undefined || !!options.finalize,

    ...options, // to make sure the options from the tests override the default ones
    gasPriceLimit: "2000000000000",
    spendLimitPeriod: "259200",
    spendLimitEth: "2000000000000000000000",
    feePercent: "110",
    gasFixed: "50000",
    gelato: "0x1000000000000000000000000000000000000000",
  };
};

const advanceTime = async (time) => {
  await new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: "2.0",
        method: "evm_increaseTime",
        params: [time],
        id: new Date().getTime(),
      },
      (err, result) => {
        if (err) {
          return reject(err);
        }
        return resolve(result);
      }
    );
  });

  await new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: "2.0",
        method: "evm_mine",
        id: new Date().getTime(),
      },
      (err, result) => {
        if (err) {
          return reject(err);
        }
        return resolve(result);
      }
    );
  });

  return true;
};

const takeChainSnapshot = async () => {
  return await new Promise((resolve, reject) =>
    provider.send(
      {
        jsonrpc: "2.0",
        method: "evm_snapshot",
        id: new Date().getTime(),
      },
      (err, result) => {
        if (err) {
          return reject(err);
        }
        let snapshotId = result.result; // {"id":X,"jsonrpc":"2.0","result":"0x..."}
        return resolve(snapshotId);
      }
    )
  );
};

const revertChainSnapshot = async (snapshotId) => {
  return await new Promise((resolve, reject) =>
    provider.send(
      {
        jsonrpc: "2.0",
        method: "evm_revert",
        params: [snapshotId],
        id: new Date().getTime(),
      },
      (err, result) => {
        if (err) {
          return reject(err);
        }
        return resolve(result);
      }
    )
  ).catch((e) => console.error(e));
};

const proposalIdGenerator = () => {
  var idCounter = 0;
  return {
    *generator() {
      idCounter++;
      const str = "" + idCounter;

      return `0x${str.padStart(64, "0")}`;
    },
  };
};

module.exports = (() => {
  const ozContracts = getOpenZeppelinContracts(allContractConfigs);

  const deployMyDao = async (options) => {
    const { WETH } = ozContracts;
    const weth = await WETH.new();
    const finalize = options.finalize === undefined ? true : options.finalize;

    const result = await deployDao({
      ...getDefaultOptions(options),
      ...ozContracts,
      deployFunction,
      attachFunction: attach,
      contractConfigs: allContractConfigs,
      weth: weth.address,
      finalize: false,
    });

    if (finalize) await result.dao.finalizeDao({ from: options.owner });

    return { wethContract: weth, ...result };
  };

  const deployDefaultDao = async (options) => {
    const { WETH } = ozContracts;
    const weth = await WETH.new();
    const finalize = options.finalize === undefined ? true : options.finalize;

    const result = await deployDao({
      ...getDefaultOptions(options),
      ...ozContracts,
      deployFunction,
      attachFunction: attach,
      contractConfigs: allContractConfigs,
      weth: weth.address,
      finalize: false,
    });

    if (finalize) await result.dao.finalizeDao({ from: options.owner });

    return { wethContract: weth, ...result };
  };

  const deployDefaultNFTDao = async ({ owner }) => {
    const { WETH } = ozContracts;
    const weth = await WETH.new();

    const { dao, adapters, extensions, testContracts, utilContracts } =
      await deployDao({
        ...getDefaultOptions({ owner }),
        ...ozContracts,
        deployFunction,
        attachFunction: attach,
        finalize: false,
        contractConfigs: allContractConfigs,
        weth: weth.address,
        wethContract: weth,
      });

    await dao.finalizeDao({ from: owner });

    return {
      dao: dao,
      adapters: adapters,
      extensions: extensions,
      testContracts: testContracts,
      utilContracts: utilContracts,
      wethContract: weth,
    };
  };

  const deployDaoWithOffchainVoting = async (options) => {
    const owner = options.owner;
    const newMember = options.newMember;

    const { WETH } = ozContracts;
    const weth = await WETH.new();
    const { dao, adapters, extensions, testContracts, votingHelpers } =
      await deployDao({
        ...getDefaultOptions(options),
        ...ozContracts,
        deployFunction,
        attachFunction: attach,
        finalize: false,
        offchainVoting: true,
        offchainAdmin: owner,
        contractConfigs: allContractConfigs,
        weth: weth.address,
      });

    if (newMember) {
      await dao.potentialNewMember(newMember, {
        from: owner,
      });

      await extensions.bankExt.addToBalance(dao.address, newMember, UNITS, 1, {
        from: owner,
      });
    }

    await dao.finalizeDao({ from: owner });

    return {
      dao: dao,
      adapters: adapters,
      extensions: extensions,
      testContracts: testContracts,
      votingHelpers: votingHelpers,
      wethContract: weth,
    };
  };

  const generateMembers = (amount) => {
    let newAccounts = [];
    for (let i = 0; i < amount; i++) {
      const account = web3.eth.accounts.create();
      newAccounts.push(account);
    }
    return newAccounts;
  };

  const encodeProposalData = (dao, proposalId) =>
    web3.eth.abi.encodeParameter(
      {
        ProcessProposal: {
          dao: "address",
          proposalId: "bytes32",
        },
      },
      {
        dao: dao.address,
        proposalId,
      }
    );

  return {
    web3,
    provider,
    accounts,
    expect,
    expectRevert,
    getBalance,
    generateMembers,
    deployMyDao,
    deployDefaultDao,
    deployDefaultNFTDao,
    deployDaoWithOffchainVoting,
    encodeProposalData,
    takeChainSnapshot,
    revertChainSnapshot,
    proposalIdGenerator,
    advanceTime,
    deployFunction,
    attachFunction: attach,
    getContractFromOpenZeppelin,
    ...ozContracts,
  };
})();
