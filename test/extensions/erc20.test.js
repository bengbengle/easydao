// Whole-script strict mode syntax
"use strict";

const { toBN, sha3, unitPrice, UNITS, ZERO_ADDRESS, numberOfUnits } = require("../../utils/contract-util");

const { takeChainSnapshot, revertChainSnapshot, proposalIdGenerator, accounts, expectRevert, expect, web3, deployDefaultDao } = require("../../utils/oz-util");

const { isMember, onboardingNewMember, submitConfigProposal } = require("../../utils/test-util");

const proposalCounter = proposalIdGenerator().generator;

function getProposalCounter() {
  return proposalCounter().next().value;
}

describe("Extension - ERC20", () => {
  const daoOwner = accounts[0];

  before("deploy dao", async () => {
    const { dao, adapters, extensions, testContracts } = await deployDefaultDao(
      { owner: daoOwner }
    );
    this.dao = dao;
    this.adapters = adapters;
    this.extensions = extensions;
    this.testContracts = testContracts;
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
    //members A
    const applicantA = accounts[2];
    //external address - not a member
    const externalAddressA = accounts[4];

    const bank = this.extensions.bankExt;
    const onboarding = this.adapters.onboarding;
    const configuration = this.adapters.configuration;
    const voting = this.adapters.voting;
    const erc20Ext = this.extensions.erc20Ext;
    
    await submitConfigProposal(
      dao,
      getProposalCounter(),
      daoOwner,
      configuration,
      voting,
      [
        { key: sha3("erc20.transfer.type"), numericValue: 1, addressValue: ZERO_ADDRESS, configType: 0 },
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
    
    // console.log('numberOfUnits.toNumber().toString()::', numberOfUnits.toNumber());
    // console.log('unitPrice.toString()::', unitPrice.toString());

    // member A units
    let applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(await isMember(bank, applicantA)).equal(true);

    // externalAddressA is not a member
    expect(await isMember(bank, externalAddressA)).equal(false);

    let externalAddressAUnits = await erc20Ext.balanceOf(externalAddressA);
    expect(externalAddressAUnits.toString()).equal(
      numberOfUnits.mul(toBN("0")).toString()
    );

    // transfer from memberA to externalAddressA
    await erc20Ext.transfer(externalAddressA, numberOfUnits.mul(toBN("1")), {
      from: applicantA,
    });

    // externalAddressA should have +1 unit
    externalAddressAUnits = await erc20Ext.balanceOf(externalAddressA);
    expect(externalAddressAUnits.toString()).equal( numberOfUnits.mul(toBN("1")).toString() );

    // externalAddressA
    expect(await isMember(bank, externalAddressA)).equal(true);

    // applicantA should have -1 unit
    applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal( numberOfUnits.mul(toBN("2")).toString() );

  });

  // 当转账类型 1 时（外部转账），可以 approve 和 transferFrom units 从 成员 到 外部账户
  it("should be possible to approve and transferFrom units from a member to an external account when the transfer type is equals 1 (external transfer)", async () => {
    // transfer to external
    const dao = this.dao;
    //members A and B
    const applicantA = accounts[2];
    const applicantB = accounts[3];
    //external address - not a member
    const externalAddressA = accounts[4];
    const externalAddressB = accounts[5];

    const bank = this.extensions.bankExt;
    const onboarding = this.adapters.onboarding;
    const configuration = this.adapters.configuration;
    const voting = this.adapters.voting;
    const erc20Ext = this.extensions.erc20Ext;
    
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
          configType: 0,
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

    await onboardingNewMember(
      getProposalCounter(),
      dao,
      onboarding,
      voting,
      applicantB,
      daoOwner,
      unitPrice,
      UNITS,
      toBN("3")
    );

    //check B's balance
    let applicantBUnits = await erc20Ext.balanceOf(applicantB);
    expect(applicantBUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(await isMember(bank, applicantB)).equal(true);

    // approve and check spender's allownance
    await erc20Ext.approve(externalAddressA, numberOfUnits.mul(toBN("1")), { from: applicantA });
    let spenderAllowance = await erc20Ext.allowance(applicantA, externalAddressA);
    expect(spenderAllowance.toString()).equal( numberOfUnits.mul(toBN("1")).toString() );

    // externallAddressB 不是成员
    expect(await isMember(bank, externalAddressB)).equal(false);

    // 转移申请人 applicantA  的金额 spenderAllowance 到 外部地址 externalAddressA
    await erc20Ext.transferFrom(applicantA, externalAddressB, numberOfUnits.mul(toBN("1")), { from: externalAddressA });

    // 查看 申请人 applicantA 和 外部成员账户 externalAddressB 的新余额
    applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal( numberOfUnits.mul(toBN("2")).toString() );

    let externalAddressBUnits = await erc20Ext.balanceOf(externalAddressB);
    expect(externalAddressBUnits.toString()).equal( numberOfUnits.mul(toBN("1")).toString() );

    //check allowance of spender -
    spenderAllowance = await erc20Ext.allowance(applicantA, externalAddressA);
    expect(spenderAllowance.toString()).equal(
      numberOfUnits.mul(toBN("0")).toString()
    );
    //externalAddressB is now a member after receiving unit
    expect(await isMember(bank, externalAddressB)).equal(true);
  });

  // 应该可以读取代币持有者的历史余额
  it("should be possible to read the historical balance of a token holder", async () => {
    const dao = this.dao;
    const applicantA = accounts[2];
    const onboarding = this.adapters.onboarding;
    const voting = this.adapters.voting;
    const erc20Ext = this.extensions.erc20Ext;

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

    // 保存区块号 以便稍后 查看历史余额
    const blockNumber = await web3.eth.getBlockNumber();

    // 查看 A 的 当前余额
    const currentUnits = await erc20Ext.balanceOf(applicantA);
    expect(currentUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );

    // 加入 另一个成员 以创建更多 blocks
    await onboardingNewMember(
      getProposalCounter(),
      dao,
      onboarding,
      voting,
      accounts[3], //applicant B
      daoOwner,
      unitPrice,
      UNITS,
      toBN("5")
    );

    // 使用保存的 区块号 查看 A 的 历史余额
    const historicalUnits = await erc20Ext.getPriorAmount(applicantA, blockNumber);
    
    expect(historicalUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
  });

  // 可以使用预配置的 erc20 扩展创建一个 dao
  it("should be possible to create a dao with a erc20 extension pre-configured", async () => {
    const erc20Ext = this.extensions.erc20Ext;
    expect(erc20Ext).to.not.be.null;
  });

  // 当转移类型等于 0 时， 应该可以将单位从一个成员转移到另一个成员（仅限成员转移）
  it("should be possible to transfer units from one member to another when the transfer type is equals 0 (member transfer only)", async () => {
    const dao = this.dao;
    const applicantA = accounts[2];
    const applicantB = accounts[3];
    const configuration = this.adapters.configuration;
    const bank = this.extensions.bankExt;
    const onboarding = this.adapters.onboarding;
    const voting = this.adapters.voting;
    const erc20Ext = this.extensions.erc20Ext;

    //configure
    await submitConfigProposal(
      dao,
      getProposalCounter(),
      daoOwner,
      configuration,
      voting,
      [
        {
          key: sha3("erc20.transfer.type"),
          numericValue: 0,
          addressValue: ZERO_ADDRESS,
          configType: 0,
        },
      ]
    );
    let transferType = await dao.getConfiguration(sha3("erc20.transfer.type"));
    expect(transferType.toString()).equal("0");

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

    let applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(await isMember(bank, applicantA)).equal(true);

    await onboardingNewMember(
      getProposalCounter(),
      dao,
      onboarding,
      voting,
      applicantB,
      daoOwner,
      unitPrice,
      UNITS,
      toBN("3")
    );

    let applicantBUnits = await erc20Ext.balanceOf(applicantB);
    expect(applicantBUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(await isMember(bank, applicantB)).equal(true);

    await erc20Ext.transfer(applicantB, numberOfUnits.mul(toBN("1")), {
      from: applicantA,
    });

    applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal(
      numberOfUnits.mul(toBN("2")).toString()
    );

    applicantBUnits = await erc20Ext.balanceOf(applicantB);
    expect(applicantBUnits.toString()).equal(
      numberOfUnits.mul(toBN("4")).toString()
    );
  });

  // 当传输类型等于 0 时， 应该可以批准和 transferFrom 单位从一个成员到另一个成员（仅限成员转移）
  it("should be possible to approve and transferFrom units from a member to another member when the transfer type is equals 0 (member transfer only)", async () => {
    const dao = this.dao;
    //onboarded member A & B
    const applicantA = accounts[2];
    const applicantB = accounts[3];
    const configuration = this.adapters.configuration;
    //external address - not a member
    const externalAddressA = accounts[4];
    const bank = this.extensions.bankExt;
    const onboarding = this.adapters.onboarding;
    const voting = this.adapters.voting;
    const erc20Ext = this.extensions.erc20Ext;

    //configure
    await submitConfigProposal(
      dao,
      getProposalCounter(),
      daoOwner,
      configuration,
      voting,
      [
        {
          key: sha3("erc20.transfer.type"),
          numericValue: 0,
          addressValue: ZERO_ADDRESS,
          configType: 0,
        },
      ]
    );
    let transferType = await dao.getConfiguration(sha3("erc20.transfer.type"));
    expect(transferType.toString()).equal("0");

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
    //check A's balance
    let applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(await isMember(bank, applicantA)).equal(true);

    await onboardingNewMember(
      getProposalCounter(),
      dao,
      onboarding,
      voting,
      applicantB,
      daoOwner,
      unitPrice,
      UNITS,
      toBN("3")
    );
    //check B's balance
    let applicantBUnits = await erc20Ext.balanceOf(applicantB);
    expect(applicantBUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(await isMember(bank, applicantB)).equal(true);

    //approve and check spender's allownance
    await erc20Ext.approve(externalAddressA, numberOfUnits.mul(toBN("1")), {
      from: applicantA,
    });
    let spenderAllowance = await erc20Ext.allowance(
      applicantA,
      externalAddressA
    );
    expect(spenderAllowance.toString()).equal(
      numberOfUnits.mul(toBN("1")).toString()
    );

    //transferFrom Applicant A(member) to ApplicantB(member) by the spender(non-member externalAddressA)
    await erc20Ext.transferFrom(
      applicantA,
      applicantB,
      numberOfUnits.mul(toBN("1")),
      { from: externalAddressA }
    );

    //check new balances of A & B
    applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal(
      numberOfUnits.mul(toBN("2")).toString()
    );
    applicantBUnits = await erc20Ext.balanceOf(applicantB);
    expect(applicantBUnits.toString()).equal(
      numberOfUnits.mul(toBN("4")).toString()
    );

    //check allowance of spender
    spenderAllowance = await erc20Ext.allowance(applicantA, externalAddressA);
    expect(spenderAllowance.toString()).equal(
      numberOfUnits.mul(toBN("0")).toString()
    );
  });

  // 转账类型为 0 时，不能将单位从会员转移到外部账户（仅限会员转移）
  it("should not be possible to transfer units from a member to an external account when the transfer type is equals 0 (member transfer only)", async () => {
    // transferFrom to external
    // transfer to external
    const dao = this.dao;
    //onboarded member A & B
    const applicantA = accounts[2];
    const applicantB = accounts[3];
    //external address - not a member
    const externalAddressA = accounts[4];
    const externalAddressB = accounts[5];
    const bank = this.extensions.bankExt;
    const onboarding = this.adapters.onboarding;
    const configuration = this.adapters.configuration;
    const voting = this.adapters.voting;
    const erc20Ext = this.extensions.erc20Ext;

    await submitConfigProposal(
      dao,
      getProposalCounter(),
      daoOwner,
      configuration,
      voting,
      [
        {
          key: sha3("erc20.transfer.type"),
          numericValue: 0,
          addressValue: ZERO_ADDRESS,
          configType: 0,
        },
      ]
    );
    let transferType = await dao.getConfiguration(sha3("erc20.transfer.type"));
    expect(transferType.toString()).equal("0");

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
    //check A's balance
    let applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    //applicantA should be a member
    expect(await isMember(bank, applicantA)).equal(true);

    //externalAddress A should not be a member
    expect(await isMember(bank, externalAddressA)).equal(false);

    //check externalAddressA's balance
    let externalAddressAUnits = await erc20Ext.balanceOf(externalAddressA);
    expect(externalAddressAUnits.toString()).equal(
      numberOfUnits.mul(toBN("0")).toString()
    );
    //attempt transfer to non-member External address A - should revert
    await expectRevert(
      erc20Ext.transfer(externalAddressA, numberOfUnits.mul(toBN("1")), {
        from: applicantA,
      }),
      "transfer not allowed"
    );

    //check balances of externalAddressA
    externalAddressAUnits = await erc20Ext.balanceOf(externalAddressA);
    expect(externalAddressAUnits.toString()).equal(
      numberOfUnits.mul(toBN("0")).toString()
    );
  });

  // 当转移类型等于 0 时，应该不能 批准从成员到外部帐户的 transferFrom 单位（仅限成员转移）
  it("should not be possible to approve a transferFrom units from a member to an external account when the transfer type is equals 0 (member transfer only)", async () => {
    // transfer to external
    const dao = this.dao;
    //onboarded member A & B
    const applicantA = accounts[2];
    const applicantB = accounts[3];
    //external address - not a member
    const externalAddressA = accounts[4];
    const externalAddressB = accounts[5];
    const bank = this.extensions.bankExt;
    const onboarding = this.adapters.onboarding;
    const configuration = this.adapters.configuration;
    const voting = this.adapters.voting;
    const erc20Ext = this.extensions.erc20Ext;

    await submitConfigProposal(
      dao,
      getProposalCounter(),
      daoOwner,
      configuration,
      voting,
      [
        {
          key: sha3("erc20.transfer.type"),
          numericValue: 0,
          addressValue: ZERO_ADDRESS,
          configType: 0,
        },
      ]
    );
    let transferType = await dao.getConfiguration(sha3("erc20.transfer.type"));
    expect(transferType.toString()).equal("0");

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
    //check A's balance
    let applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(await isMember(bank, applicantA)).equal(true);

    await onboardingNewMember(
      getProposalCounter(),
      dao,
      onboarding,
      voting,
      applicantB,
      daoOwner,
      unitPrice,
      UNITS,
      toBN("3")
    );
    //check B's balance
    let applicantBUnits = await erc20Ext.balanceOf(applicantB);
    expect(applicantBUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(await isMember(bank, applicantB)).equal(true);

    //approve and check spender's allownance
    await erc20Ext.approve(externalAddressA, numberOfUnits.mul(toBN("1")), {
      from: applicantA,
    });
    let spenderAllowance = await erc20Ext.allowance(
      applicantA,
      externalAddressA
    );
    expect(spenderAllowance.toString()).equal(
      numberOfUnits.mul(toBN("1")).toString()
    );
    //externallAddressB should not be a member
    expect(await isMember(bank, externalAddressB)).equal(false);

    //transferFrom Applicant A(member) to externalAddressB(non-member) by the spender(non-member externalAddressA) should fail
    await expectRevert(
      erc20Ext.transferFrom(
        applicantA,
        externalAddressB,
        numberOfUnits.mul(toBN("1")),
        { from: externalAddressA }
      ),
      "transfer not allowed"
    );

    //check new balances of applicantA & externalAddressB
    applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    let externalAddressBUnits = await erc20Ext.balanceOf(externalAddressB);
    expect(externalAddressBUnits.toString()).equal(
      numberOfUnits.mul(toBN("0")).toString()
    );

    //check allowance of spender - should remain the same, since it could not be spent
    spenderAllowance = await erc20Ext.allowance(applicantA, externalAddressA);
    expect(spenderAllowance.toString()).equal(
      numberOfUnits.mul(toBN("1")).toString()
    );
  });

  // 当传输类型  2 时, 可以 pause 所有传输（暂停所有传输）
  it("should be possible to pause all transfers when the transfer type is equals 2 (paused all transfers)", async () => {
    const dao = this.dao;
    //onboarded members A & B
    const applicantA = accounts[2];
    const applicantB = accounts[3];

    const bank = this.extensions.bankExt;
    const onboarding = this.adapters.onboarding;
    const configuration = this.adapters.configuration;
    const voting = this.adapters.voting;
    const erc20Ext = this.extensions.erc20Ext;
    //configure to pause all transfers
    await submitConfigProposal(
      dao,
      getProposalCounter(),
      daoOwner,
      configuration,
      voting,
      [
        {
          key: sha3("erc20.transfer.type"),
          numericValue: 2,
          addressValue: ZERO_ADDRESS,
          configType: 0,
        },
      ]
    );
    let transferType = await dao.getConfiguration(sha3("erc20.transfer.type"));
    expect(transferType.toString()).equal("2");
    //onboard A
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
    //check A's balance
    let applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(await isMember(bank, applicantA)).equal(true);
    //onboard B
    await onboardingNewMember(
      getProposalCounter(),
      dao,
      onboarding,
      voting,
      applicantB,
      daoOwner,
      unitPrice,
      UNITS,
      toBN("3")
    );
    //check B's balance
    let applicantBUnits = await erc20Ext.balanceOf(applicantB);
    expect(applicantBUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(await isMember(bank, applicantB)).equal(true);

    //attempt transfer
    await expectRevert(
      erc20Ext.transfer(applicantB, numberOfUnits.mul(toBN("1")), {
        from: applicantA,
      }),
      "transfer not allowed"
    );

    //applicantA should still have the same number of Units
    applicantAUnits = await erc20Ext.balanceOf(applicantA);
    expect(applicantAUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    //applicantB should still have the same number of Units
    applicantBUnits = await erc20Ext.balanceOf(applicantB);
    expect(applicantBUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
  });

});
