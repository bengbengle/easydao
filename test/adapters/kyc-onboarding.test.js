// Whole-script strict mode syntax
"use strict";

const {
  toBN,
  toWei,
  unitPrice,
  UNITS,
  GUILD,
  ETH_TOKEN,
  remaining,
  numberOfUnits,
} = require("../../utils/contract-util.js");

const {
  deployDefaultDao,
  takeChainSnapshot,
  revertChainSnapshot,
  accounts,
  expectRevert,
  expect,
  OLToken,
  getBalance,
} = require("../../utils/oz-util.js");

const { checkBalance, isMember } = require("../../utils/test-util.js");
const daoOwner = accounts[0];

const {
  SigUtilSigner,
  getMessageERC712Hash,
} = require("../../utils/offchain-voting-util.js");

const signer = {
  address: "0x7D8cad0bbD68deb352C33e80fccd4D8e88b4aBb8",
  privKey: "c150429d49e8799f119434acd3f816f299a5c7e3891455ee12269cb47a5f987c",
};

describe("Adapter - KYC Onboarding", () => {
  before("deploy dao", async () => {
    const { dao, adapters, extensions, wethContract } = await deployDefaultDao({
      owner: daoOwner,
    });
    this.dao = dao;
    this.weth = wethContract;
    this.adapters = adapters;
    this.extensions = extensions;
    this.snapshotId = await takeChainSnapshot();
  });

  beforeEach(async () => {
    await revertChainSnapshot(this.snapshotId);
    this.snapshotId = await takeChainSnapshot();
  });

  // 当 代币数量 超过 外部代币 限制时， 应该无法加入
  it("should not be possible onboard when the token amount exceeds the external token limits", async () => {
    const applicant = accounts[2];

    // Issue OpenLaw ERC20 Basic Token for tests
    // Token supply higher than the limit for external tokens
    // 为测试发行 OpenLaw ERC20 基本代币， 代币 供应量 高于 外部代币的限制

    const nbOfERC20Units = 100000000;
    const erc20UnitPrice = toBN("10");

    const { dao, adapters } = await deployDefaultDao({
      owner: daoOwner,
      unitPrice: erc20UnitPrice,
      nbUnits: nbOfERC20Units,
      tokenAddr: ETH_TOKEN,
    });

    const onboarding = adapters.kycOnboarding;

    const initialTokenBalance = await getBalance(applicant);

    await expectRevert(
      onboarding.onboardEth(dao.address, applicant, [], {
        from: applicant,
        gasPrice: toBN("0"),
      }),
      "Returned error: VM Exception while processing transaction: revert"
    );

    // In case of failures the funds must be in the applicant account
    // 如果失败，资金必须在申请人账户中
    const applicantTokenBalance = await getBalance(applicant);
    // "applicant account should contain 2**161 OLT Tokens when the onboard fails"
    // “加入失败时，申请账户应包含 2**161 个 OLT Tokens”
    expect(initialTokenBalance.toString()).equal(
      applicantTokenBalance.toString()
    );
  });

  // 可以加入 具有 ERC-20 贡献的 DAO
  it("should be possible to join a DAO with ERC-20 contribution", async () => {
    const applicant = accounts[2];
    const nonMemberAccount = accounts[3];
    const tokenSupply = toBN("10000000000000000000000");
    const oltContract = await OLToken.new(tokenSupply);

    const { dao, adapters, extensions, wethContract } = await deployDefaultDao({
      owner: daoOwner,
      tokenAddr: oltContract.address,
    });

    const bank = extensions.bankExt;
    const onboarding = adapters.kycOnboarding;

    const myAccountInitialBalance = await getBalance(applicant);
    // remaining amount to test sending back to proposer
    // 用于测试的 剩余金额 发送回 提议者
    const ethAmount = unitPrice.mul(toBN(3)).add(remaining);

    const signerUtil = SigUtilSigner(signer.privKey);

    const couponData = {
      type: "coupon-kyc",
      kycedMember: applicant,
    };

    let jsHash = getMessageERC712Hash(
      couponData,
      dao.address,
      onboarding.address,
      1
    );
    let solHash = await onboarding.hashCouponMessage(dao.address, couponData);
    expect(jsHash).equal(solHash);

    const signature = signerUtil(
      couponData,
      dao.address,
      onboarding.address,
      1
    );

    await oltContract.transfer(applicant, toWei("1"));

    await oltContract.approve(onboarding.address, toWei("1"), {
      from: applicant,
    });

    await onboarding.onboard(
      dao.address,
      applicant,
      oltContract.address,
      toWei("1"),
      signature,
      {
        from: applicant,
        gasPrice: toBN("0"),
      }
    );

    // test return of remaining amount in excess of multiple of unitsPerChunk
    const myAccountBalance = await getBalance(applicant);
    // daoOwner did not receive remaining amount in excess of multiple of unitsPerChunk
    expect(myAccountBalance.toString()).equal("1000000000000000000000000");

    const myAccountUnits = await bank.balanceOf(daoOwner, UNITS);
    const applicantUnits = await bank.balanceOf(applicant, UNITS);
    const nonMemberAccountUnits = await bank.balanceOf(nonMemberAccount, UNITS);
    expect(myAccountUnits.toString()).equal("1");
    expect(applicantUnits.toString()).equal(
      numberOfUnits.mul(toBN("8")).toString()
    );
    expect(nonMemberAccountUnits.toString()).equal("0");
    await checkBalance(bank, GUILD, ETH_TOKEN, 0);
    const fundTargetAddress = "0x823A19521A76f80EC49670BE32950900E8Cd0ED3";
    const balance = await oltContract.balanceOf(fundTargetAddress);

    expect(balance.toString()).equal(unitPrice.mul(toBN("8")).toString());
    // test active member status
    const applicantIsActiveMember = await isMember(bank, applicant);
    expect(applicantIsActiveMember).equal(true);
    const nonMemberAccountIsActiveMember = await isMember(
      bank,
      nonMemberAccount
    );
    expect(nonMemberAccountIsActiveMember).equal(false);
  });

  // 应该可以加入一个有 ETH 贡献的 DAO
  it("should be possible to join a DAO with ETH contribution", async () => {
    const applicant = accounts[2];
    const nonMemberAccount = accounts[3];

    const dao = this.dao;
    const bank = this.extensions.bankExt;
    const onboarding = this.adapters.kycOnboarding;

    const myAccountInitialBalance = await getBalance(applicant);
    // remaining amount to test sending back to proposer
    const ethAmount = unitPrice.mul(toBN(3)).add(remaining);

    const signerUtil = SigUtilSigner(signer.privKey);

    const couponData = {
      type: "coupon-kyc",
      kycedMember: applicant,
    };

    let jsHash = getMessageERC712Hash(
      couponData,
      dao.address,
      onboarding.address,
      1
    );
    let solHash = await onboarding.hashCouponMessage(dao.address, couponData);
    expect(jsHash).equal(solHash);

    const signature = signerUtil(
      couponData,
      dao.address,
      onboarding.address,
      1
    );

    await onboarding.onboardEth(dao.address, applicant, signature, {
      from: applicant,
      value: ethAmount,
      gasPrice: toBN("0"),
    });

    // test return of remaining amount in excess of multiple of unitsPerChunk
    const myAccountBalance = await getBalance(applicant);
    // daoOwner did not receive remaining amount in excess of multiple of unitsPerChunk
    expect(
      toBN(myAccountInitialBalance).sub(ethAmount).add(remaining).toString()
    ).equal(myAccountBalance.toString());

    const myAccountUnits = await bank.balanceOf(daoOwner, UNITS);
    const applicantUnits = await bank.balanceOf(applicant, UNITS);
    const nonMemberAccountUnits = await bank.balanceOf(nonMemberAccount, UNITS);
    expect(myAccountUnits.toString()).equal("1");
    expect(applicantUnits.toString()).equal(
      numberOfUnits.mul(toBN("3")).toString()
    );
    expect(nonMemberAccountUnits.toString()).equal("0");
    await checkBalance(bank, GUILD, ETH_TOKEN, 0);
    const fundTargetAddress = "0x823A19521A76f80EC49670BE32950900E8Cd0ED3";
    const balance = await this.weth.balanceOf(fundTargetAddress);

    expect(balance.toString()).equal(unitPrice.mul(toBN("3")).toString());
    // test active member status
    const applicantIsActiveMember = await isMember(bank, applicant);
    expect(applicantIsActiveMember).equal(true);
    const nonMemberAccountIsActiveMember = await isMember(
      bank,
      nonMemberAccount
    );
    expect(nonMemberAccountIsActiveMember).equal(false);
  });

  it("should not be possible to join the same member after he delegates his membership to another address", async () => {
    const applicant = accounts[2];
    const delegateKey = accounts[3];

    const dao = this.dao;
    const onboarding = this.adapters.kycOnboarding;
    const daoRegistryAdapter = this.adapters.daoRegistryAdapter;

    const myAccountInitialBalance = await getBalance(applicant);
    // remaining amount to test sending back to proposer
    const ethAmount = unitPrice.mul(toBN(3)).add(remaining);

    const signerUtil = SigUtilSigner(signer.privKey);

    const couponData = {
      type: "coupon-kyc",
      kycedMember: applicant,
    };

    let jsHash = getMessageERC712Hash(
      couponData,
      dao.address,
      onboarding.address,
      1
    );
    let solHash = await onboarding.hashCouponMessage(dao.address, couponData);
    expect(jsHash).equal(solHash);

    const signature = signerUtil(
      couponData,
      dao.address,
      onboarding.address,
      1
    );

    await onboarding.onboardEth(dao.address, applicant, signature, {
      from: applicant,
      value: ethAmount,
      gasPrice: toBN("0"),
    });

    // test return of remaining amount in excess of multiple of unitsPerChunk
    const myAccountBalance = await getBalance(applicant);
    // daoOwner did not receive remaining amount in excess of multiple of unitsPerChunk
    expect(
      toBN(myAccountInitialBalance).sub(ethAmount).add(remaining).toString()
    ).equal(myAccountBalance.toString());

    await daoRegistryAdapter.updateDelegateKey(dao.address, delegateKey, {
      from: applicant,
      gasPrice: toBN("0"),
    });

    await expectRevert(
      onboarding.onboardEth(dao.address, applicant, signature, {
        from: delegateKey,
        value: ethAmount,
        gasPrice: toBN("0"),
      }),
      "already member"
    );
  });

  // 不应超过 最大单位数
  it("should not be possible to have more than the maximum number of units", async () => {
    const applicant = accounts[2];
    const dao = this.dao;
    const onboarding = this.adapters.kycOnboarding;

    const signerUtil = SigUtilSigner(signer.privKey);

    const couponData = {
      type: "coupon-kyc",
      kycedMember: applicant,
    };

    const signature = signerUtil(
      couponData,
      dao.address,
      onboarding.address,
      1
    );

    await expectRevert(
      onboarding.onboardEth(dao.address, applicant, signature, {
        from: daoOwner,
        value: unitPrice.mul(toBN(100)).add(remaining),
        gasPrice: toBN("0"),
      }),
      "too much funds"
    );
  });
});
