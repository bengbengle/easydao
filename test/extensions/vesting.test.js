// Whole-script strict mode syntax
"use strict";

const { UNITS, toBN } = require("../../utils/contract-util");

const { toNumber } = require("web3-utils");

const {
  takeChainSnapshot,
  revertChainSnapshot,
  deployDefaultDao,
  advanceTime,
  accounts,
  expect,
  expectRevert,
} = require("../../utils/oz-util");

describe("Extension - Vesting", () => {
  const daoOwner = accounts[0];

  before("deploy dao", async () => {
    const { dao, adapters, extensions, testContracts } = await deployDefaultDao(
      { owner: daoOwner, finalize: false }
    );
    this.dao = dao;
    this.adapters = adapters;
    this.extensions = extensions;
    this.testContracts = testContracts;
    this.snapshotId = await takeChainSnapshot();
  });

  beforeEach(async () => {
    this.snapshotId = await takeChainSnapshot();
  });

  afterEach(async () => {
    await revertChainSnapshot(this.snapshotId);
  });

  // 应该能够创建归属，并且冻结的金额应该随时间 而变化
  it("should be able to create vesting and the blocked amount should change with time", async () => {
    const vesting = this.extensions.vestingExt;
    const now = new Date();

    const numberOfDaysToAdd = 6;
    now.setDate(now.getDate() + numberOfDaysToAdd);
    let minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(minBalance.toString()).equal("0");

    await vesting.createNewVesting(
      this.dao.address,
      daoOwner,
      UNITS,
      1000,
      Math.floor(now.getTime() / 1000),
      { from: daoOwner }
    );

    const v = await vesting.vesting(daoOwner, UNITS);
    const diff = toBN(v.endDate.toString()).sub(toBN(v.startDate.toString()));

    minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(minBalance.toString()).equal("1000");

    const halfWay = diff.div(toBN("2"));

    await advanceTime(halfWay.toNumber());

    minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(toBN(minBalance.toString())).to.be.closeTo(toBN("500"), 5);

    await advanceTime(diff.toNumber());

    minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(minBalance.toString()).equal("0");
  });

  // 应该能够添加多个归属
  it("should be able to add multiple vestings", async () => {
    const vesting = this.extensions.vestingExt;
    const now = new Date();

    const numberOfDaysToAdd = 6;
    now.setDate(now.getDate() + numberOfDaysToAdd);
    let minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(minBalance.toString()).equal("0");

    await vesting.createNewVesting(
      this.dao.address,
      daoOwner,
      UNITS,
      100,
      Math.floor(now.getTime() / 1000),
      { from: daoOwner }
    );

    let v = await vesting.vesting(daoOwner, UNITS);
    let diff = toBN(v.endDate.toString()).sub(toBN(v.startDate.toString()));

    minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(minBalance.toString()).equal("100");

    let halfWay = diff.div(toBN("2"));

    await advanceTime(halfWay.toNumber());

    now.setDate(now.getDate() + numberOfDaysToAdd);

    await vesting.createNewVesting(
      this.dao.address,
      daoOwner,
      UNITS,
      100,
      Math.floor(now.getTime() / 1000),
      { from: daoOwner }
    );

    v = await vesting.vesting(daoOwner, UNITS);
    diff = toBN(v.endDate.toString()).sub(toBN(v.startDate.toString()));
    halfWay = diff.div(toBN("2"));

    minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(toBN(minBalance.toString())).to.be.closeTo(toBN("150"), 5);

    await advanceTime(halfWay.toNumber());

    minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(toBN(minBalance.toString())).to.be.closeTo(toBN("75"), 5);

    await advanceTime(diff.toNumber());

    minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(minBalance.toString()).equal("0");
  });

  // 应该可以取消归属
  it("should be possible to remove vesting", async () => {
    const vesting = this.extensions.vestingExt;
    const now = new Date();

    const numberOfDaysToAdd = 6;
    now.setDate(now.getDate() + numberOfDaysToAdd);
    let minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(minBalance.toString()).equal("0");

    await vesting.createNewVesting(
      this.dao.address,
      daoOwner,
      UNITS,
      100,
      Math.floor(now.getTime() / 1000),
      { from: daoOwner }
    );

    let v = await vesting.vesting(daoOwner, UNITS);
    let diff = toBN(v.endDate.toString()).sub(toBN(v.startDate.toString()));

    minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(minBalance.toString()).equal("100");

    let halfWay = diff.div(toBN("2"));

    await advanceTime(halfWay.toNumber());

    now.setDate(now.getDate() + numberOfDaysToAdd);

    await vesting.createNewVesting(
      this.dao.address,
      daoOwner,
      UNITS,
      100,
      Math.floor(now.getTime() / 1000),
      { from: daoOwner }
    );

    v = await vesting.vesting(daoOwner, UNITS);
    diff = toBN(v.endDate.toString()).sub(toBN(v.startDate.toString()));
    halfWay = diff.div(toBN("2"));

    minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    const minBalanceStr = minBalance.toString();

    expect(toNumber(minBalanceStr)).to.be.closeTo(150, 1);

    await advanceTime(halfWay.toNumber());

    minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(toNumber(minBalance.toString())).to.be.closeTo(75, 1);

    await vesting.removeVesting(this.dao.address, daoOwner, UNITS, 50, {
      from: daoOwner,
    });

    minBalance = await vesting.getMinimumBalance(daoOwner, UNITS);
    expect(toNumber(minBalance.toString())).to.be.closeTo(25, 1);
  });

  // 没有 ACL 权限应该不可能创建新的归属
  it("should not be possible to create a new vesting without the ACL permission", async () => {
    // 完成 DAO 以便能够检查扩展权限
    await this.dao.finalizeDao({ from: daoOwner });
    const vesting = this.extensions.vestingExt;
    const now = new Date();
    await expectRevert(
      vesting.createNewVesting(
        this.dao.address,
        daoOwner,
        UNITS,
        100,
        Math.floor(now.getTime() / 1000),
        { from: daoOwner }
      ),
      "vestingExt::accessDenied"
    );
  });

  // 在没有 ACL 权限的情况下，应该无法删除归属计划
  it("should not be possible to removeVesting a vesting schedule the without ACL permission", async () => {

    await this.dao.finalizeDao({ from: daoOwner });

    const vesting = this.extensions.vestingExt;
    await expectRevert(
      vesting.removeVesting(this.dao.address, daoOwner, UNITS, 100, {
        from: daoOwner,
      }),
      "vestingExt::accessDenied"
    );
  });
});
