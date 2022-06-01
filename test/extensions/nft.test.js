// Whole-script strict mode syntax
"use strict";

const { toBN, sha3, unitPrice, UNITS, ZERO_ADDRESS, numberOfUnits } = require("../../utils/contract-util");

const { takeChainSnapshot, revertChainSnapshot, proposalIdGenerator, accounts, expectRevert, expect, web3, deployDefaultDao } = require("../../utils/oz-util");

const { isMember, onboardingNewMember, submitConfigProposal } = require("../../utils/test-util");

const proposalCounter = proposalIdGenerator().generator;

function getProposalCounter() {
  return proposalCounter().next().value;
}

describe("Extension - ERC721", () => {
  const daoOwner = accounts[0];

  before("deploy dao", async () => {
    
    const { dao, adapters, extensions, testContracts } = await deployDefaultDao({ owner: daoOwner });

    this.dao = dao;
    this.adapters = adapters;
    this.extensions = extensions;
    // this.testContracts = testContracts;
  });

  beforeEach(async () => {
    this.snapshotId = await takeChainSnapshot();
  });

  afterEach(async () => {
    await revertChainSnapshot(this.snapshotId);
  });
   
  
  // 当转账类型 1 时（外部转账），可以 transfer units  到 外部账户
  it("should be possible to transfer units from a member to an external account when the transfer type is equals 1 (external transfer)", async () => {
    
    // transfer to external
    const dao = this.dao;
    // members A
    const applicantA = accounts[2];
    // external address - not a member
    const externalAddressA = accounts[4];

    const bank = this.extensions.bankExt;
    const erc20Ext = this.extensions.erc20Ext;

    const onboarding = this.adapters.onboarding;
    const configuration = this.adapters.configuration;
    const voting = this.adapters.voting;
    
    await submitConfigProposal(
      dao,
      getProposalCounter(),
      daoOwner,
      configuration,
      voting,
      [
        { 
          key: sha3("erc20.transfer.type"), 
          numericValue: 1, 
          addressValue: ZERO_ADDRESS, 
          configType: 0 
        },
      ]
    );
    
    let transferType = await dao.getConfiguration(sha3("erc20.transfer.type"));
    expect(transferType.toString()).equal("1");
    
    // onboard memberA
    await onboardingNewMember(
      getProposalCounter(),
      dao,
      onboarding,
      voting,
      applicantA,
      daoOwner,
      unitPrice,
      UNITS,
      toBN("3")
    );
    
    // member A units
    let applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(await isMember(bank, applicantA)).equal(true);

    // externalAddressA is not a member
    // 开始时候，成员 externalAddressA 不是成员
    expect(await isMember(bank, externalAddressA)).equal(false);

    let externalAddressAUnits = await erc20Ext.balanceOf(externalAddressA);
    expect(externalAddressAUnits.toString()).equal(
      numberOfUnits.mul(toBN("0")).toString()
    );

    // transfer from memberA to externalAddressA
    // 从账户 memberA 转移到外部账户 externalAddressA
    await erc20Ext.transfer(externalAddressA, numberOfUnits.mul(toBN("1")), {
      from: applicantA,
    });

    // externalAddressA should have +1 unit
    // externalAddressA 应该有 +1 个单位
    externalAddressAUnits = await erc20Ext.balanceOf(externalAddressA);
    expect(externalAddressAUnits.toString()).equal( numberOfUnits.mul(toBN("1")).toString() );

    // externalAddressA
    expect(await isMember(bank, externalAddressA)).equal(true);

    // applicantA should have -1 unit
    applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal( numberOfUnits.mul(toBN("2")).toString() );

  });
});
