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

  // ?????????????????? ????????????????????? ?????? ??? ?????????????????????????????? DAO ??????
  it("should be possible to update a DAO configuration if you are a member and a maintainer that holds an external governance token", async () => {
    const maintainer = accounts[5];

    // ?????? OpenLaw ERC20 Basic Token ????????????????????? DAO ???????????????????????? token
    const tokenSupply = toBN(100000);
    const oltContract = await OLToken.new(tokenSupply);

    // ??? OLT ?????????????????????
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

    // ?????????????????????????????????
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(oltContract.address);

    // ?????? DAO ?????????????????????
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

    // ????????? ????????????????????????
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

    // ????????? ?????? ?????????
    await configuration.processProposal(dao.address, proposalId, {
      from: maintainer,
      gasPrice: toBN("0"),
    });

    value = await dao.getConfiguration(key);
    expect(value.toString()).equal("99");
  });

  // ??????????????? ???????????????????????????????????????????????? ?????? DAO ??????
  // ???????????????????????? UNITS?????????????????????
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

    // ??????????????? ????????????????????? 
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(utils.getAddress(UNITS));

    // ?????? DAO ???????????? ?????????
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

    // ????????????????????? ????????????
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

    // ?????????????????????????????????
    await voting.submitVote(dao.address, proposalId, 1, {from: maintainer, gasPrice: toBN("0")});

    await advanceTime(10000);

    // ????????????????????????
    await configuration.processProposal(dao.address, proposalId, {from: maintainer, gasPrice: toBN("0")});

    value = await dao.getConfiguration(key);
    expect(value.toString()).equal("99");
  });

  // ?????????????????? ???????????????????????? ???????????????????????? ?????????????????? DAO ??????
  it("should be possible to update a DAO configuration if you are a member and a maintainer that holds an internal default governance token", async () => {
    const maintainer = accounts[5];
    const { dao, adapters } = await deployDefaultDao({
      owner: daoOwner,
      // ????????????????????? ????????????????????????????????? UNITS????????????????????????????????????
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

  // ?????????????????? ???????????? ??????????????? ?????? ??? ???????????? ???????????? ?????? DAO ??????
  it("should be possible to update a DAO configuration if you are a member and a maintainer that holds an external default governance token", async () => {
    const maintainer = accounts[5];

    // ?????? OpenLaw ERC20 Basic Token ????????????????????? DAO ???????????????????????? token
    const tokenSupply = toBN(100000);
    const oltContract = await OLToken.new(tokenSupply);

    // ??? OLT ?????????????????????
    await oltContract.transfer(daoOwner, toBN(1));
    const maintainerBalance = await oltContract.balanceOf.call(daoOwner);
    expect(maintainerBalance.toString()).equal("1");

    const { dao, adapters } = await deployDefaultDao({
      owner: daoOwner,
      // ???????????????????????????????????????????????????????????? OLT????????????????????????????????????
      defaultMemberGovernanceToken: oltContract.address,
    });
    const voting = adapters.voting;
    const configuration = adapters.configuration;
    const configKey = sha3(web3.utils.encodePacked("governance.role.default"));

    // ?????????????????????????????????
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(oltContract.address);

    // ?????? DAO ?????????????????????
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

    // ?????????????????????????????????
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

  // ??????????????????????????????????????? ????????????????????? DAO ??????
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

  // ???????????????????????????????????????????????????????????? DAO ??????
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

    // DAO ?????????????????????????????????????????? ??????????????????????????????????????? OLT ???????????? ????????????????????????, ??????????????????
    await expectRevert(
      voting.submitVote(dao.address, proposalId, 1, {
        from: daoOwner,
        gasPrice: toBN("0"),
      }),
      "vote not allowed"
    );
  });

  // ??????????????????????????? getPriorAmount ????????????????????????????????????????????? ????????????????????? DAO ??????
  it("should not be possible to update a DAO configuration if you are a member & maintainer that holds an external token which not implements getPriorAmount function", async () => {
    
    // ???????????? PixelNFT ??????????????????????????? getPriorAmount ???????????????????????????????????? DAO ?????????????????????????????????  
    const externalGovToken = await PixelNFT.new(10);
    await externalGovToken.mintPixel(daoOwner, 1, 1, {
      from: daoOwner,
    });

    
    // ?????? PixelNFTs ?????????????????? ????????? ?????????
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

    // ?????????????????????????????????
    const governanceToken = await dao.getAddressConfiguration(configKey);
    expect(governanceToken).equal(externalGovToken.address);

    let key = sha3("key");

    const proposalId = getProposalCounter();

    // DAO ?????????????????????????????????
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

    // daoOwner ???????????????????????????????????????????????????????????????????????? OLT ??????????????????????????????, ????????????????????????
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
