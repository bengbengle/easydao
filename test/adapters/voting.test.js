// Whole-script strict mode syntax
"use strict";

const { utils } = require("ethers");
const {
  toBN,
  toWei,
  fromAscii,
  sha3,
  unitPrice,
  remaining,
  ZERO_ADDRESS,
  UNITS,
} = require("../../utils/contract-util");

const {
  deployDefaultDao,
  takeChainSnapshot,
  revertChainSnapshot,
  proposalIdGenerator,
  advanceTime,
  accounts,
  expectRevert,
  expect,
  web3,
  OLToken,
  PixelNFT,
} = require("../../utils/oz-util");

const { onboardingNewMember } = require("../../utils/test-util");

describe("Adapter - Voting", () => {
  const daoOwner = accounts[1];
  const proposalCounter = proposalIdGenerator().generator;

  const getProposalCounter = () => {
    return proposalCounter().next().value;
  };

  before("deploy dao", async () => {
    const { dao, adapters, extensions } = await deployDefaultDao({owner: daoOwner});
    this.dao = dao;
    this.adapters = adapters;
    this.extensions = extensions;
    this.snapshotId = await takeChainSnapshot();
  });

  beforeEach(async () => {
    await revertChainSnapshot(this.snapshotId);
    this.snapshotId = await takeChainSnapshot();
  });

  it("should be possible to vote", async () => {
    const account2 = accounts[2];
    const dao = this.dao;
    const onboarding = this.adapters.onboarding;
    const voting = this.adapters.voting;

    const proposalId = getProposalCounter();
    await onboarding.submitProposal(
      dao.address,
      proposalId,
      account2,
      UNITS,
      unitPrice.mul(toBN(3)).add(remaining),
      [],
      {
        from: daoOwner,
        gasPrice: toBN("0"),
      }
    );

    await voting.submitVote(dao.address, proposalId, 1, {
      from: daoOwner,
      gasPrice: toBN("0"),
    });

    await advanceTime(10000);
    const vote = await voting.voteResult(dao.address, proposalId);
    expect(vote.toString()).equal("2"); // vote should be "pass = 2"
  });

  it("should not be possible to vote twice", async () => {
    const account2 = accounts[2];
    const dao = this.dao;
    const onboarding = this.adapters.onboarding;
    const voting = this.adapters.voting;

    const proposalId = getProposalCounter();
    await onboarding.submitProposal(
      dao.address,
      proposalId,
      account2,
      UNITS,
      unitPrice.mul(toBN(3)).add(remaining),
      [],
      {
        from: daoOwner,
        gasPrice: toBN("0"),
      }
    );

    await voting.submitVote(dao.address, proposalId, 1, {
      from: daoOwner,
      gasPrice: toBN("0"),
    });

    await expectRevert(
      voting.submitVote(dao.address, proposalId, 2, {
        from: daoOwner,
        gasPrice: toBN("0"),
      }),
      "member has already voted"
    );
  });

  it("should not be possible to vote with a non-member address", async () => {
    const account2 = accounts[2];
    const account3 = accounts[3];
    const dao = this.dao;
    const onboarding = this.adapters.onboarding;
    const voting = this.adapters.voting;

    const proposalId = getProposalCounter();
    await onboarding.submitProposal(
      dao.address,
      proposalId,
      account2,
      UNITS,
      unitPrice.mul(toBN(3)).add(remaining),
      [],
      {
        from: daoOwner,
        gasPrice: toBN("0"),
      }
    );

    await expectRevert(
      voting.submitVote(dao.address, proposalId, 1, {
        from: account3,
        gasPrice: toBN("0"),
      }),
      "onlyMember"
    );
  });

  it("should be possible to vote with a delegate non-member address", async () => {
    const account2 = accounts[2];
    const account3 = accounts[3];
    const dao = this.dao;
    const onboarding = this.adapters.onboarding;
    const voting = this.adapters.voting;
    const daoRegistryAdapter = this.adapters.daoRegistryAdapter;

    const proposalId = getProposalCounter();
    await onboarding.submitProposal(
      dao.address,
      proposalId,
      account2,
      UNITS,
      unitPrice.mul(toBN(3)).add(remaining),
      [],
      {
        from: daoOwner,
        gasPrice: toBN("0"),
      }
    );

    await daoRegistryAdapter.updateDelegateKey(dao.address, account3, {
      from: daoOwner,
      gasPrice: toBN("0"),
    });

    await voting.submitVote(dao.address, proposalId, 1, {
      from: account3,
      gasPrice: toBN("0"),
    });

    await advanceTime(10000);
    const vote = await voting.voteResult(dao.address, proposalId);
    expect(vote.toString()).equal("2"); // vote should be "pass = 2"
  });

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

  // 如果您是持有 外部治理令牌的 成员 和 维护者，应该可以更新 DAO 配置
  it("should be possible to update a DAO configuration if you are a member and a maintainer that holds an external governance token", async () => {
    const maintainer = accounts[5];

    // 发行 OpenLaw ERC20 Basic Token 进行测试，只有 DAO 维护者会持有这个 token
    const tokenSupply = toBN(100000);
    const oltContract = await OLToken.new(tokenSupply);

    // 将 OLT 转入维护者账户
    await oltContract.transfer(maintainer, toBN(1));
    const maintainerBalance = await oltContract.balanceOf.call(maintainer);
    expect(maintainerBalance.toString()).equal("1");

    const { dao, adapters } = await deployDefaultDao({
      owner: daoOwner,
      maintainerTokenAddress: oltContract.address,
    });

    const voting = adapters.voting;
    const configuration = adapters.configuration;
    const configKey = sha3(web3.utils.encodePacked("governance.role.", utils.getAddress(configuration.address)));

    // 确保已创建治理令牌配置
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(oltContract.address);

    // 作为 DAO 成员加入维护者
    await onboardingNewMember(
      getProposalCounter(),
      dao,
      adapters.onboarding,
      voting,
      maintainer,
      daoOwner,
      unitPrice,
      UNITS
    );

    const key = sha3("key");
    const proposalId = getProposalCounter();

    // 维护者 提交新的配置提案
    await configuration.submitProposal(
      dao.address,
      proposalId,
      [
        {
          key: key,
          numericValue: 99,
          addressValue: ZERO_ADDRESS,
          configType: 0,
        },
      ],
      [],
      { from: maintainer, gasPrice: toBN("0") }
    );

    let value = await dao.getConfiguration(key);
    expect(value.toString()).equal("0");

    // The maintainer votes on the new proposal
    await voting.submitVote(dao.address, proposalId, 1, {
      from: maintainer,
      gasPrice: toBN("0"),
    });

    await advanceTime(10000);

    // 维护者 处理 新提案
    await configuration.processProposal(dao.address, proposalId, {
      from: maintainer,
      gasPrice: toBN("0"),
    });

    value = await dao.getConfiguration(key);
    expect(value.toString()).equal("99");
  });

  // 如果您持有 内部治理令牌的成员和维护者，可以 更新 DAO 配置
  // 如果会员持有任何 UNITS，他就是维护者
  it("should be possible to update a DAO configuration if you are a member and a maintainer that holds an internal governance token", async () => {
    const maintainer = accounts[5];
    const { dao, adapters } = await deployDefaultDao({
      owner: daoOwner,
      maintainerTokenAddress: UNITS,
    });
    const voting = adapters.voting;
    const configuration = adapters.configuration;
    const configKey = sha3(
      web3.utils.encodePacked("governance.role.", utils.getAddress(configuration.address))
    );

    // 确保已创建 治理令牌的配置 
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(utils.getAddress(UNITS));

    // 作为 DAO 成员加入 维护者
    await onboardingNewMember(
      getProposalCounter(),
      dao,
      adapters.onboarding,
      voting,
      maintainer,
      daoOwner,
      unitPrice,
      UNITS
    );

    const key = sha3("key");
    const proposalId = getProposalCounter();

    // 维护者提交新的 配置提案
    await configuration.submitProposal(
      dao.address,
      proposalId,
      [
        {
          key: key,
          numericValue: 99,
          addressValue: ZERO_ADDRESS,
          configType: 0,
        },
      ],
      [],
      { from: maintainer, gasPrice: toBN("0") }
    );

    let value = await dao.getConfiguration(key);
    expect(value.toString()).equal("0");

    // 维护者对新提案进行投票
    await voting.submitVote(dao.address, proposalId, 1, {from: maintainer, gasPrice: toBN("0")});

    await advanceTime(10000);

    // 维护者处理新提案
    await configuration.processProposal(dao.address, proposalId, {from: maintainer, gasPrice: toBN("0")});

    value = await dao.getConfiguration(key);
    expect(value.toString()).equal("99");
  });

  // 如果您是持有 内部默认治理令牌 的成员和维护者， 应该可以更新 DAO 配置
  it("should be possible to update a DAO configuration if you are a member and a maintainer that holds an internal default governance token", async () => {
    const maintainer = accounts[5];
    const { dao, adapters } = await deployDefaultDao({
      owner: daoOwner,
      // 如果该成员持有 任何代表默认治理令牌的 UNITS，则该成员被视为维护者。
      defaultMemberGovernanceToken: UNITS,
    });
    const voting = adapters.voting;
    const configuration = adapters.configuration;
    const configKey = sha3(web3.utils.encodePacked("governance.role.default"));

    // Make sure the governance token configuration was created
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(utils.getAddress(UNITS));

    // Onboard the maintainer as a DAO member
    await onboardingNewMember(
      getProposalCounter(),
      dao,
      adapters.onboarding,
      voting,
      maintainer,
      daoOwner,
      unitPrice,
      UNITS
    );

    const key = sha3("key");
    const proposalId = getProposalCounter();

    // The maintainer submits a new configuration proposal
    await configuration.submitProposal(
      dao.address,
      proposalId,
      [
        {
          key: key,
          numericValue: 99,
          addressValue: ZERO_ADDRESS,
          configType: 0,
        },
      ],
      [],
      { from: maintainer, gasPrice: toBN("0") }
    );

    let value = await dao.getConfiguration(key);
    expect(value.toString()).equal("0");

    // The maintainer votes on the new proposal
    await voting.submitVote(dao.address, proposalId, 1, {
      from: maintainer,
      gasPrice: toBN("0"),
    });

    await advanceTime(10000);

    // The maintainer processes on the new proposal
    await configuration.processProposal(dao.address, proposalId, {
      from: maintainer,
      gasPrice: toBN("0"),
    });

    value = await dao.getConfiguration(key);
    expect(value.toString()).equal("99");
  });

  // 如果您是持有 外部默认 治理令牌的 成员 和 维护者， 应该可以 更新 DAO 配置
  it("should be possible to update a DAO configuration if you are a member and a maintainer that holds an external default governance token", async () => {
    const maintainer = accounts[5];

    // 发行 OpenLaw ERC20 Basic Token 进行测试，只有 DAO 维护者会持有这个 token
    const tokenSupply = toBN(100000);
    const oltContract = await OLToken.new(tokenSupply);

    // 将 OLT 转入维护者账户
    await oltContract.transfer(daoOwner, toBN(1));
    const maintainerBalance = await oltContract.balanceOf.call(daoOwner);
    expect(maintainerBalance.toString()).equal("1");

    const { dao, adapters } = await deployDefaultDao({
      owner: daoOwner,
      // 如果该成员持有任何代表外部默认治理令牌的 OLT，则该成员被视为维护者。
      defaultMemberGovernanceToken: oltContract.address,
    });
    const voting = adapters.voting;
    const configuration = adapters.configuration;
    const configKey = sha3(web3.utils.encodePacked("governance.role.default"));

    // 确保已创建治理令牌配置
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(oltContract.address);

    // 作为 DAO 成员加入维护者
    await onboardingNewMember(
      getProposalCounter(),
      dao,
      adapters.onboarding,
      voting,
      maintainer,
      daoOwner,
      unitPrice,
      UNITS
    );

    const key = sha3("key");
    const proposalId = getProposalCounter();

    // 维护者提交新的配置提案
    await configuration.submitProposal(
      dao.address,
      proposalId,
      [
        {
          key: key,
          numericValue: 99,
          addressValue: ZERO_ADDRESS,
          configType: 0,
        },
      ],
      [],
      { from: maintainer, gasPrice: toBN("0") }
    );

    let value = await dao.getConfiguration(key);
    expect(value.toString()).equal("0");

    // The maintainer votes on the new proposal
    await voting.submitVote(dao.address, proposalId, 1, {
      from: maintainer,
      gasPrice: toBN("0"),
    });

    await advanceTime(10000);

    // The maintainer processes on the new proposal
    await configuration.processProposal(dao.address, proposalId, {
      from: maintainer,
      gasPrice: toBN("0"),
    });

    value = await dao.getConfiguration(key);
    expect(value.toString()).equal("99");
  });

  // 如果您是维护者但不是成员， 则应该无法更新 DAO 配置
  it("should not be possible to update a DAO configuration if you are a maintainer but not a member", async () => {
    const maintainer = accounts[5]; // not a member

    // Issue OpenLaw ERC20 Basic Token for tests, only DAO maintainer will hold this token
    const tokenSupply = toBN(100000);
    const oltContract = await OLToken.new(tokenSupply);

    // Transfer OLTs to the maintainer account
    await oltContract.transfer(maintainer, toBN(1));
    const maintainerBalance = await oltContract.balanceOf.call(maintainer);
    expect(maintainerBalance.toString()).equal("1");

    const { dao, adapters } = await deployDefaultDao({
      owner: daoOwner,
      maintainerTokenAddress: oltContract.address, // only holders of the OLT token are considered maintainers
    });
    const configuration = adapters.configuration;
    const configKey = sha3(
      web3.utils.encodePacked(
        "governance.role.",
        utils.getAddress(configuration.address)
      )
    );

    // Make sure the governance token configuration was created
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(oltContract.address);

    let key = sha3("key");

    const proposalId = getProposalCounter();
    //Submit a new configuration proposal
    await expectRevert(
      configuration.submitProposal(
        dao.address,
        proposalId,
        [
          {
            key: key,
            numericValue: 99,
            addressValue: ZERO_ADDRESS,
            configType: 0,
          },
        ],
        [],
        { from: maintainer, gasPrice: toBN("0") }
      ),
      "onlyMember"
    );
  });

  // 如果您是成员但不是维护者，则应该无法更新 DAO 配置
  it("should not be possible to update a DAO configuration if you are a member but not a maintainer", async () => {
    // Issue OpenLaw ERC20 Basic Token for tests, only DAO maintainer will hold this token
    const tokenSupply = toBN(100000);
    const oltContract = await OLToken.new(tokenSupply);

    const { dao, adapters } = await deployDefaultDao({
      owner: daoOwner,
      // only holders of the OLT tokens are considered
      // maintainers
      maintainerTokenAddress: oltContract.address,
    });
    const voting = adapters.voting;
    const configuration = adapters.configuration;
    const configKey = sha3(
      web3.utils.encodePacked(
        "governance.role.",
        utils.getAddress(configuration.address)
      )
    );

    // Make sure the governance token configuration was created
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(oltContract.address);

    let key = sha3("key");

    const proposalId = getProposalCounter();

    // The DAO owner submits a new configuration proposal
    await configuration.submitProposal(
      dao.address,
      proposalId,
      [
        {
          key: key,
          numericValue: 99,
          addressValue: ZERO_ADDRESS,
          configType: 0,
        },
      ],
      [],
      {
        from: daoOwner, // The DAO Owner is not a maintainer because does not hold any OLT Tokens
        gasPrice: toBN("0"),
      }
    );

    let value = await dao.getConfiguration(key);
    expect(value.toString()).equal("0");

    // DAO 所有者尝试对新提案进行投票， 但由于他不是维护者（不持有 OLT 代币）， 因此投票权重为零, 因此不能投票
    await expectRevert(
      voting.submitVote(dao.address, proposalId, 1, {
        from: daoOwner,
        gasPrice: toBN("0"),
      }),
      "vote not allowed"
    );
  });

  // 如果您是持有未实现 getPriorAmount 函数的外部令牌的成员和维护者， 则应该无法更新 DAO 配置
  it("should not be possible to update a DAO configuration if you are a member & maintainer that holds an external token which not implements getPriorAmount function", async () => {
    
    // 铸造一个 PixelNFT 以将其用作没有实现 getPriorAmount 函数的外部治理令牌。只有 DAO 维护者会持有这个令牌。  
    const externalGovToken = await PixelNFT.new(10);
    await externalGovToken.mintPixel(daoOwner, 1, 1, {
      from: daoOwner,
    });

    
    // 只有 PixelNFTs 代币的持有者 能成为 维护者
    const { dao, adapters } = await deployDefaultDao({
      owner: daoOwner,
      maintainerTokenAddress: externalGovToken.address,

    });
    const voting = adapters.voting;
    const configuration = adapters.configuration;
    const configKey = sha3(
      web3.utils.encodePacked(
        "governance.role.",
        utils.getAddress(configuration.address)
      )
    );

    // 确保已创建治理令牌配置
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(externalGovToken.address);

    let key = sha3("key");

    const proposalId = getProposalCounter();

    // DAO 所有者提交新的配置提案
    await configuration.submitProposal(
      dao.address,
      proposalId,
      [
        {
          key: key,
          numericValue: 11,
          addressValue: ZERO_ADDRESS,
          configType: 0,
        },
      ],
      [],
      {
        from: daoOwner, // The DAO Owner is not a maintainer because does not hold any OLT Tokens
        gasPrice: toBN("0"),
      }
    );

    let value = await dao.getConfiguration(key);
    expect(value.toString()).equal("0");

    // daoOwner 尝试对新提案进行投票，但由于他不是维护者（不持有 OLT 代币），投票权重为零, 因此不应允许投票
    // await expectRevert(
    //   voting.submitVote(dao.address, proposalId, 1, {
    //     from: daoOwner,
    //     gasPrice: toBN("0"),
    //   }),
    //   "getPriorAmount not implemented"
    // );


    
    // The maintainer votes on the new proposal
    await voting.submitVote(dao.address, proposalId, 1, {
      from: daoOwner,
      gasPrice: toBN("0"),
    });

    await advanceTime(10000);

    // The daoOwner processes on the new proposal
    await configuration.processProposal(dao.address, proposalId, {
      from: daoOwner,
      gasPrice: toBN("0"),
    });

    value = await dao.getConfiguration(key);
    expect(value.toString()).equal("11");

  });
});
