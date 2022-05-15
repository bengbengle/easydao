// Whole-script strict mode syntax
"use strict";

const { utils } = require("ethers");
const {
  toBN,
  toWei,
  sha3,
  fromAscii,
  unitPrice,
  remaining,
  UNITS,
  TOTAL,
  MEMBER_COUNT,
  ZERO_ADDRESS,
} = require("../../utils/contract-util");
const { log } = require("../../utils/log-util");

const {
  proposalIdGenerator,
  advanceTime,
  deployDaoWithOffchainVoting,
  accounts,
  expect,
  expectRevert,
  takeChainSnapshot,
  revertChainSnapshot,
  web3,
  generateMembers,
  OffchainVotingHashContract,
  OLToken,
  PixelNFT,
} = require("../../utils/oz-util");

const {
  createVote,
  getDomainDefinition,
  TypedDataUtils,
  prepareProposalPayload,
  prepareVoteProposalData,
  prepareProposalMessage,
  prepareVoteResult,
  SigUtilSigner,
  getVoteStepDomainDefinition,
  BadNodeError,
} = require("../../utils/offchain-voting-util");

const members = generateMembers(10);
const findMember = (addr) => members.find((member) => member.address === addr);
const daoOwner = accounts[0];
const newMember = members[0];
const proposalCounter = proposalIdGenerator().generator;

function getProposalCounter() {
  return proposalCounter().next().value;
}

const onboardMember = async (dao, voting, onboarding, bank, index) => {
  const blockNumber = await web3.eth.getBlockNumber();
  const proposalId = getProposalCounter();

  const proposalPayload = {
    name: "some proposal",
    body: "this is my proposal",
    choices: ["yes", "no"],
    start: Math.floor(new Date().getTime() / 1000),
    end: Math.floor(new Date().getTime() / 1000) + 10000,
    snapshot: blockNumber.toString(),
  };

  const space = "tribute";
  const chainId = 1;

  // 提案 包含的数据
  const proposalData = {
    type: "proposal",
    timestamp: Math.floor(new Date().getTime() / 1000),
    space,
    payload: proposalPayload,
    submitter: members[0].address,
  };

  // myAccount 的签名者（其私钥）， 
  const signer = SigUtilSigner(members[0].privateKey);
  proposalData.sig = await signer(proposalData, dao.address, onboarding.address, chainId);

  await onboarding.submitProposal(
    dao.address,
    proposalId,
    members[index].address,
    UNITS,
    unitPrice.mul(toBN(3)).add(remaining),
    prepareVoteProposalData(proposalData, web3),
    {
      from: daoOwner,
      gasPrice: toBN("0"),
    }
  );
  
  // 投票的 列表
  const voteEntries = [];
  const membersCount = await dao.getNbMembers();

  for (let i = 0; i < parseInt(membersCount.toString()) - 1; i++) {
    const memberAddress = await dao.getMemberAddress(i);
    const member = findMember(memberAddress);
    let voteEntry;
    if (member) {
      const voteSigner = SigUtilSigner(member.privateKey);
      const weight = await bank.balanceOf(member.address, UNITS);

      voteEntry = await createVote(proposalId, weight, true);

      voteEntry.sig = voteSigner(voteEntry, dao.address, onboarding.address, chainId);
    } else {
      voteEntry = await createVote(proposalId, 0, true);

      voteEntry.sig = "0x";
    }

    voteEntries.push(voteEntry);
  }

  await advanceTime(10000);


  const { voteResultTree, result } = await prepareVoteResult(voteEntries, dao, onboarding.address, chainId);

  const rootSig = signer(
    { root: voteResultTree.getHexRoot(), type: "result" },
    dao.address,
    onboarding.address,
    chainId
  );

  const lastResult = result[result.length - 1];

  await voting.submitVoteResult(dao.address, proposalId, voteResultTree.getHexRoot(), members[0].address, lastResult, rootSig);

  await advanceTime(10000);

  await onboarding.processProposal(dao.address, proposalId, {
    value: unitPrice.mul(toBN("3")).add(remaining),
  });
};

const updateConfiguration = async (
  dao,
  voting,
  configuration,
  bank,
  index,
  configs,
  singleVote = false,
  processProposal = true
) => {
  const blockNumber = await web3.eth.getBlockNumber();
  const proposalId = getProposalCounter();

  const proposalPayload = {
    name: "new configuration proposal",
    body: "testing the governance token",
    choices: ["yes", "no"],
    start: Math.floor(new Date().getTime() / 1000),
    end: Math.floor(new Date().getTime() / 1000) + 10000,
    snapshot: blockNumber.toString(),
  };

  const space = "tribute";
  const chainId = 1;

  const proposalData = {
    type: "proposal",
    timestamp: Math.floor(new Date().getTime() / 1000),
    space,
    payload: proposalPayload,
    submitter: members[index].address,
  };

  //myAccount 的签名者（其私钥）
  const signer = SigUtilSigner(members[index].privateKey);
  proposalData.sig = await signer(
    proposalData,
    dao.address,
    configuration.address,
    chainId
  );
  const data = prepareVoteProposalData(proposalData, web3);
  await configuration.submitProposal(dao.address, proposalId, configs, data, {
    from: daoOwner,
    gasPrice: toBN("0"),
  });

  const membersCount = await bank.getPriorAmount(TOTAL, MEMBER_COUNT, blockNumber);
  const voteEntries = [];
  const maintainer = members[index];
  for (let i = 0; i < parseInt(membersCount.toString()); i++) {
    const memberAddress = await dao.getMemberAddress(i);
    const member = findMember(memberAddress);
    let voteEntry;
    const voteYes = singleVote ? memberAddress === maintainer.address : true;
    if (member) {
      const voteSigner = SigUtilSigner(member.privateKey);
      const weight = await bank.balanceOf(member.address, UNITS);
      voteEntry = await createVote(
        proposalId,
        toBN(weight.toString()),
        voteYes
      );
      voteEntry.sig = voteSigner(
        voteEntry,
        dao.address,
        configuration.address,
        chainId
      );
    } else {
      voteEntry = await createVote(proposalId, toBN("0"), voteYes);
      voteEntry.sig = "0x";
    }

    voteEntries.push(voteEntry);
  }

  await advanceTime(10000);

  const { voteResultTree, result } = await prepareVoteResult(
    voteEntries,
    dao,
    configuration.address,
    chainId
  );

  const rootSig = signer(
    { root: voteResultTree.getHexRoot(), type: "result" },
    dao.address,
    configuration.address,
    chainId
  );

  const lastResult = result[result.length - 1];
  lastResult.nbYes = lastResult.nbYes.toString();
  lastResult.nbNo = lastResult.nbNo.toString();
  const submitter = members[index].address;

  if (processProposal) {
    await voting.submitVoteResult(
      dao.address,
      proposalId,
      voteResultTree.getHexRoot(),
      members[index].address,
      lastResult,
      rootSig
    );

    await advanceTime(10000);

    // The maintainer processes on the new proposal
    // 维护者处理新提案
    await configuration.processProposal(dao.address, proposalId);
  }

  return {
    proposalId,
    voteResultTree,
    blockNumber,
    membersCount,
    lastResult,
    submitter,
    rootSig,
  };
};

describe("Adapter - Offchain Voting", () => {
  before("deploy dao", async () => {
    const { dao, adapters, extensions, votingHelpers } =
      await deployDaoWithOffchainVoting({
        owner: daoOwner,
        newMember: newMember.address,
      });
    this.dao = dao;
    this.adapters = adapters;
    this.extensions = extensions;
    this.votingHelpers = votingHelpers;
    this.snapshotId = await takeChainSnapshot();
  });

  beforeEach(async () => {
    await revertChainSnapshot(this.snapshotId);
    this.snapshotId = await takeChainSnapshot();
  });

  
  // ------------- 检查 javascript 和 solidity 是否 一致 -------------------------------------- 

  // 对于 javascript 和 solidity 之间的提案，类型和哈希 是否应该一致
  it("should type & hash be consistent for proposals between javascript and solidity", async () => {
    const dao = this.dao;

    let blockNumber = await web3.eth.getBlockNumber();
    const proposalPayload = {
      type: "proposal",
      name: "some proposal",
      body: "this is my proposal",
      choices: ["yes", "no"],
      start: Math.floor(new Date().getTime() / 1000),
      end: Math.floor(new Date().getTime() / 1000) + 10000,
      snapshot: blockNumber.toString(),
    };

    const proposalData = {
      type: "proposal",
      timestamp: Math.floor(new Date().getTime() / 1000),
      space: "tribute",
      payload: proposalPayload,
      submitter: members[0].address,
      sig: "0x00",
    };

    const chainId = 1;
    let { types, domain } = getDomainDefinition(
      proposalData,
      dao.address,
      daoOwner,
      chainId
    );

    const snapshotContract = this.votingHelpers.snapshotProposalContract;
    // 检查提案类型
    const solProposalMsg = await snapshotContract.PROPOSAL_MESSAGE_TYPE();
    const jsProposalMsg = TypedDataUtils.encodeType("Message", types);
    expect(jsProposalMsg).equal(solProposalMsg);

    // 检查 payload
    const hashStructPayload = "0x" + TypedDataUtils.hashStruct(
        "MessagePayload",
        prepareProposalPayload(proposalPayload),
        types,
        true
      ).toString("hex");

    const solidityHashPayload = await snapshotContract.hashProposalPayload(
      proposalPayload
    );
    expect(solidityHashPayload).equal(hashStructPayload);

    // 检查 entry payload
    const hashStruct = "0x" + TypedDataUtils.hashStruct(
        "Message",
        prepareProposalMessage(proposalData),
        types
      ).toString("hex");

    const solidityHash = await snapshotContract.hashProposalMessage(
      proposalData
    );

    expect(solidityHash).equal(hashStruct);

    // Checking domain
    const domainDef = await snapshotContract.EIP712_DOMAIN();
    const jsDomainDef = TypedDataUtils.encodeType("EIP712Domain", types);
    expect(domainDef).equal(jsDomainDef);

    // Checking domain separator
    const domainHash = await snapshotContract.DOMAIN_SEPARATOR(
      dao.address,
      daoOwner
    );

    const jsDomainHash = "0x" + TypedDataUtils.hashStruct("EIP712Domain", domain, types, true).toString(
        "hex"
      );

    expect(domainHash).equal(jsDomainHash);
  });

  // 对于 javascript 和 solidity 之间的投票，类型和哈希 是否应该一致
  it("should type & hash be consistent for votes between javascript and solidity", async () => {
    const chainId = 1;
    const dao = this.dao;
    const offchainVoting = this.votingHelpers.offchainVoting;
    const snapshotContract = this.votingHelpers.snapshotProposalContract;

    const proposalHash = sha3("test");
    const voteEntry = await createVote(proposalHash, 1, true);

    const { types } = getDomainDefinition(voteEntry, dao.address, daoOwner, chainId);

    // 检查提案类型
    const solProposalMsg = await snapshotContract.VOTE_MESSAGE_TYPE();
    const jsProposalMsg = TypedDataUtils.encodeType("Message", types);
    expect(jsProposalMsg).equal(solProposalMsg);

    // 检查 entry payload
    const hashStruct = "0x" + TypedDataUtils.hashStruct("Message", voteEntry, types).toString("hex");
    const solidityHash = await snapshotContract.hashVoteInternal(voteEntry);
    expect(hashStruct).equal(solidityHash);

    const nodeDef = getVoteStepDomainDefinition(
      dao.address,
      dao.address,
      chainId
    );

    const ovHashAddr = await offchainVoting.ovHash();
    const ovHash = await OffchainVotingHashContract.at(ovHashAddr);

    const solNodeDef = await ovHash.VOTE_RESULT_NODE_TYPE();
    const jsNodeMsg = TypedDataUtils.encodeType("Message", nodeDef.types);

    expect(solNodeDef).equal(jsNodeMsg);
  });

  // --------------------- should be possible -------------------------------------------
  
  // 应该可能通过 签署提案哈希 来 提议新 的投票
  it("should be possible to propose a new voting by signing the proposal hash", async () => {
    const dao = this.dao;
    const onboarding = this.adapters.onboarding;
    const bank = this.extensions.bankExt;

    for (var i = 1; i < members.length; i++) {
      await onboardMember(
        dao,
        this.votingHelpers.offchainVoting,
        onboarding,
        bank,
        i
      );
    }
  });

  // 如果您是持有 外部治理令牌 的成员和维护者，应该可以更新 DAO 配置
  it("should be possible to update a DAO configuration if you are a member and a maintainer that holds an external governance token", async () => {
    const accountIndex = 0;
    const maintainer = members[accountIndex];
    // 发行 OpenLaw ERC20 Basic Token 进行测试，只有 DAO 维护者会持有这个 token
    const tokenSupply = toBN(100000);
    const oltContract = await OLToken.new(tokenSupply);

    // 将 OLT 转入 维护者账户
    await oltContract.transfer(maintainer.address, toBN(1));
    const maintainerBalance = await oltContract.balanceOf.call(
      maintainer.address
    );
    expect(maintainerBalance.toString()).equal("1");

    const { dao, adapters, extensions } = await deployDaoWithOffchainVoting({
      owner: daoOwner,
      newMember: maintainer.address,
      maintainerTokenAddress: oltContract.address,
    });
    const bank = extensions.bankExt;
    const voting = adapters.voting; //这是链下投票适配器
    const configuration = adapters.configuration;
    const configKey = sha3(
      web3.utils.encodePacked(
        "governance.role.",
        utils.getAddress(configuration.address)
      )
    );
    
    // 确保已创建治理令牌配置
    // 确保已创建 治理令牌的配置
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(oltContract.address);

    const newConfigKey = sha3("new-config-a");
    const newConfigValue = toBN("10");
    const configs = [
      {
        key: newConfigKey,
        numericValue: "10",
        addressValue: ZERO_ADDRESS,
        configType: 0,
      },
    ];

    await updateConfiguration(
      dao,
      voting,
      configuration,
      bank,
      accountIndex,
      configs
    );

    const updatedConfigValue = await dao.getConfiguration(newConfigKey);
    expect(updatedConfigValue.toString()).equal(newConfigValue.toString());
  });

  // 如果您是持有 内部治理令牌的 成员和维护者，应该可以更新 DAO 配置
  it("should be possible to update a DAO configuration if you are a member and a maintainer that holds an internal governance token", async () => {
    const accountIndex = 0;
    const maintainer = members[accountIndex];

    const { dao, adapters, extensions } = await deployDaoWithOffchainVoting({
      owner: daoOwner,
      newMember: maintainer.address,
      // if the member holds any UNITS he is a maintainer
      maintainerTokenAddress: UNITS,
    });
    const bank = extensions.bankExt;
    const voting = adapters.voting; //这是链下投票适配器
    const configuration = adapters.configuration;
    const configKey = sha3(
      web3.utils.encodePacked(
        "governance.role.",
        utils.getAddress(configuration.address)
      )
    );

    // 确保已创建 治理令牌的配置
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(utils.getAddress(UNITS));

    const newConfigKey = sha3("new-config-a");
    const newConfigValue = toBN("10");
    const configs = [
      {
        key: newConfigKey,
        numericValue: "10",
        addressValue: ZERO_ADDRESS,
        configType: 0,
      },
    ];

    await updateConfiguration(
      dao,
      voting,
      configuration,
      bank,
      accountIndex,
      configs
    );

    const updatedConfigValue = await dao.getConfiguration(newConfigKey);
    expect(updatedConfigValue.toString()).equal(newConfigValue.toString());
  });

  // 如果您是持有 默认 内部治理令牌 的成员和维护者，应该可以更新 DAO 配置
  it("should be possible to update a DAO configuration if you are a member and a maintainer that holds an internal default governance token", async () => {
    const accountIndex = 0;
    const maintainer = members[accountIndex];

    const { dao, adapters, extensions } = await deployDaoWithOffchainVoting({
      owner: daoOwner,
      newMember: maintainer.address,
      // if the member holds any UNITS that represents the default governance token, the member is considered a maintainer.
      // 如果该成员持有任何代表默认治理令牌的 UNITS，则该成员被视为维护者。
      defaultMemberGovernanceToken: UNITS,
    });
    const bank = extensions.bankExt;
    const voting = adapters.voting; //这是链下投票适配器
    const configuration = adapters.configuration;
    const configKey = sha3(web3.utils.encodePacked("governance.role.default"));

    // 确保已创建 治理令牌配置
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(utils.getAddress(UNITS));

    const newConfigKey = sha3("new-config-a");
    const newConfigValue = toBN("10");
    const configs = [
      {
        key: newConfigKey,
        numericValue: "10",
        addressValue: ZERO_ADDRESS,
        configType: 0,
      },
    ];

    await updateConfiguration(
      dao,
      voting,
      configuration,
      bank,
      accountIndex,
      configs
    );

    const updatedConfigValue = await dao.getConfiguration(newConfigKey);
    expect(updatedConfigValue.toString()).equal(newConfigValue.toString());
  });

  // 如果您是持有 默认 外部治理令牌 的成员和维护者，应该可以更新 DAO 配置
  it("should be possible to update a DAO configuration if you are a member and a maintainer that holds an external default governance token", async () => {
    const accountIndex = 0;
    const maintainer = members[accountIndex];

    // 发行 OpenLaw ERC20 Basic Token 进行测试，只有 DAO 维护者会持有这个 token
    const tokenSupply = toBN(100000);
    const oltContract = await OLToken.new(tokenSupply);

    // 将 OLT 代币 转入维护者账户
    await oltContract.transfer(maintainer.address, toBN(1));

    const maintainerBalance = await oltContract.balanceOf.call(maintainer.address);
    expect(maintainerBalance.toString()).equal("1");

    // 如果该成员持有任何 默认治理令牌 OLT，该成员被视为维护者
    const { dao, adapters, extensions } = await deployDaoWithOffchainVoting({
      owner: daoOwner,
      newMember: maintainer.address,
      defaultMemberGovernanceToken: oltContract.address,
    });

    const bank = extensions.bankExt;
    const voting = adapters.voting; //这是链下投票适配器
    const configuration = adapters.configuration;
    const configKey = sha3(web3.utils.encodePacked("governance.role.default"));

    // 确保已创建 治理令牌的配置
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(oltContract.address);

    const newConfigKey = sha3("new-config-a");
    const newConfigValue = toBN("10");
    const configs = [
      {
        key: newConfigKey,
        numericValue: "10",
        addressValue: ZERO_ADDRESS,
        configType: 0,
      },
    ];

    await updateConfiguration(
      dao,
      voting,
      configuration,
      bank,
      accountIndex,
      configs
    );

    const updatedConfigValue = await dao.getConfiguration(newConfigKey);
    expect(updatedConfigValue.toString()).equal(newConfigValue.toString());
  });


  // --------- not be possible -----------------------------------------
  
  
  // 应该不可能通过接收功能向适配器发送 ETH
  it("should not be possible to send ETH to the adapter via receive function", async () => {
    const adapter = this.adapters.voting;
    await expectRevert(
      web3.eth.sendTransaction({
        to: adapter.address,
        from: daoOwner,
        gasPrice: toBN("0"),
        value: toWei("1"),
      }),
      "revert"
    );
  });

  // 应该不可能通过后备功能将 ETH 发送到适配器
  it("should not be possible to send ETH to the adapter via fallback function", async () => {
    const adapter = this.adapters.voting;
    await expectRevert(
      web3.eth.sendTransaction({
        to: adapter.address,
        from: daoOwner,
        gasPrice: toBN("0"),
        value: toWei("1"),
        data: fromAscii("should go to fallback func"),
      }),
      "revert"
    );
  });

  // 如果您是维护者但不是成员，则应该无法更新 DAO 配置
  it("should not be possible to update a DAO configuration if you are a maintainer but not a member", async () => {
    const accountIndex = 5; //not a member
    const maintainer = members[accountIndex];
    // 发行 OpenLaw ERC20 Basic Token 进行测试，只有 DAO 维护者会持有这个 token
    const tokenSupply = toBN(100000);
    const oltContract = await OLToken.new(tokenSupply);

    // 将 OLT 转入 维护者账户
    await oltContract.transfer(maintainer.address, toBN(1));
    const maintainerBalance = await oltContract.balanceOf.call(
      maintainer.address
    );
    expect(maintainerBalance.toString()).equal("1");

    const { dao, adapters, extensions } = await deployDaoWithOffchainVoting({
      owner: daoOwner,
      newMember: members[0].address,
      maintainerTokenAddress: oltContract.address,
    });

    const bank = extensions.bankExt;
    const voting = adapters.voting; //这是链下投票适配器
    const configuration = adapters.configuration;
    const configKey = sha3(web3.utils.encodePacked("governance.role.", utils.getAddress(configuration.address)));

    // 确保已创建 治理令牌的配置
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(oltContract.address);

    const newConfigKey = sha3("new-config-a");
    const configs = [
      {
        key: newConfigKey,
        numericValue: "10",
        addressValue: ZERO_ADDRESS,
        configType: 0,
      },
    ];

    await expectRevert(
      updateConfiguration(
        dao,
        voting,
        configuration,
        bank,
        accountIndex,
        configs
      ),
      "onlyMember"
    );
  });

  // 如果您是成员但不是 维护者，则应该无法更新 DAO 配置
  it("should not be possible to update a DAO configuration if you are a member but not a maintainer", async () => {
    const accountIndex = 0; // new member

    // 发行 OpenLaw ERC20 Basic Token 进行测试，只有 DAO 维护者会持有这个 token
    const tokenSupply = toBN(100000);
    const oltContract = await OLToken.new(tokenSupply);

    const { dao, adapters, extensions } = await deployDaoWithOffchainVoting({
      owner: daoOwner,
      // 添加了新成员，但不持有 OLT
      newMember: members[accountIndex].address,
      // 仅 OLT 代币的持有者 是 维护者
      maintainerTokenAddress: oltContract.address,
    });
    const bank = extensions.bankExt;
    const voting = adapters.voting; //这是链下投票适配器
    const configuration = adapters.configuration;
    const configKey = sha3(web3.utils.encodePacked("governance.role.", utils.getAddress(configuration.address)));

    // 确保已创建 治理令牌的配置
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(oltContract.address);

    const newConfigKey = sha3("new-config-a");
    const configs = [
      {
        key: newConfigKey,
        numericValue: "10",
        addressValue: ZERO_ADDRESS,
        configType: 0,
      },
    ];

    // 新成员尝试对新提案进行投票， 但由于他不是维护者 （不持有 OLT 代币） ， 投票权重为零， 因此提案不应通过   
    const data = await updateConfiguration(
      dao,
      voting,
      configuration,
      bank,
      accountIndex,
      configs,
      true, // 表示只有 1 个成员对该提案投了赞成票，但他不是维护者
      false // 跳过流程提案
    );

    await expectRevert(
      voting.submitVoteResult(
        dao.address,
        data.proposalId,
        data.voteResultTree.getHexRoot(),
        data.submitter,
        data.lastResult,
        data.rootSig
      ),
      "bad node"
    );

    // 通过调用合约验证投票结果节点
    // `gracePeriodStartingTime` is `0` as `submitNewVote` is `true`
    // `bool submitNewVote`
    const getBadNodeErrorResponse = await voting.getBadNodeError(
      dao.address,
      data.proposalId,
      true,
      data.voteResultTree.getHexRoot(),
      data.blockNumber,
      0,
      data.membersCount,
      data.lastResult
    );

    const errorCode = getBadNodeErrorResponse.toString();
    expect(BadNodeError[parseInt(errorCode)]).equal("VOTE_NOT_ALLOWED");
  });

  // 如果您是持有未实现 getPriorAmount 函数的 外部令牌的 成员 和 维护者，则应该无法更新 DAO 配置
  it("should not be possible to update a DAO configuration if you are a member & maintainer that holds an external token which not implements getPriorAmount function", async () => {
    const accountIndex = 0; 
    
    // 铸造一个 PixelNFT 以将其 未实现 getPriorAmount 函数的 外部治理令牌。 只有 DAO 维护者 会持有这个令牌  
    const externalGovToken = await PixelNFT.new(10);

    await externalGovToken.mintPixel(members[accountIndex].address, 1, 1, {from: daoOwner });

    const { dao, adapters, extensions } = await deployDaoWithOffchainVoting({
      owner: daoOwner,
      // 添加了新成员，但不持有 OLT
      newMember: members[accountIndex].address,
      // 仅 OLT 代币的持有者 是 维护者
      maintainerTokenAddress: externalGovToken.address,
    });

    const bank = extensions.bankExt;
    const voting = adapters.voting; //这是链下投票适配器
    const configuration = adapters.configuration;
    const configKey = sha3(
      web3.utils.encodePacked(
        "governance.role.",
        utils.getAddress(configuration.address)
      )
    );

    // 确保已创建 治理令牌的配置
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(externalGovToken.address);

    const newConfigKey = sha3("new-config-a");
    const configs = [
      {
        key: newConfigKey,
        numericValue: "10",
        addressValue: ZERO_ADDRESS,
        configType: 0,
      },
    ];

    // 新成员尝试对新提案进行投票， 但由于他不是维护者（不持有 OLT 代币） ，投票权重为零， 因此提案不应通过
    const data = await updateConfiguration(
      dao,
      voting,
      configuration,
      bank,
      accountIndex, // 成员的索引
      configs,
      true, // 表示只有 1 个成员对该提案投了赞成票，但他不是维护者
      false // 跳过流程提案
    );

    await expectRevert(
      voting.submitVoteResult(
        dao.address,
        data.proposalId,
        data.voteResultTree.getHexRoot(),
        data.submitter,
        data.lastResult,
        data.rootSig
      ),
      "getPriorAmount not implemented"
    );
  });
  //TODO 使用委托地址创建提案、投票并提交结果 - PASS
});
