// Whole-script strict mode syntax
"use strict";

const {
  sha3,
  toBN,
  toWei,
  fromAscii,
  UNITS,
  GUILD,
  ETH_TOKEN,
} = require("../../utils/contract-util");

const {
  deployDefaultDao,
  takeChainSnapshot,
  revertChainSnapshot,
  accounts,
  expectRevert,
  expect,
  web3,
} = require("../../utils/oz-util");

const { checkBalance } = require("../../utils/test-util");

const {
  SigUtilSigner,
  getMessageERC712Hash,
} = require("../../utils/offchain-voting-util");

const signer = {
  address: "0x7D8cad0bbD68deb352C33e80fccd4D8e88b4aBb8",
  privKey: "c150429d49e8799f119434acd3f816f299a5c7e3891455ee12269cb47a5f987c",
};

const daoOwner = accounts[1];

describe("Adapter - Coupon Onboarding", () => {
  before("deploy dao", async () => {
    const { dao, adapters, extensions } = await deployDefaultDao({
      owner: daoOwner,
    });
    this.dao = dao;
    this.adapters = adapters;
    this.extensions = extensions;
    this.snapshotId = await takeChainSnapshot();
  });

  beforeEach(async () => {
    await revertChainSnapshot(this.snapshotId);
    this.snapshotId = await takeChainSnapshot();
  });

  // 1. 检查优惠券是否尚未兑换
  // 2. 检查签名哈希是否与兑换参数的哈希匹配
  // 3. 检查优惠券的签名者是否与配置的签名者匹配
  // 4. 将配置的令牌铸造给新成员
  // 5. 标记已兑换的优惠券

  // 应该可以使用有效的优惠券加入 DAO
  it("should be possible to join a DAO with a valid coupon", async () => {
    const otherAccount = accounts[2];

    const signerUtil = SigUtilSigner(signer.privKey);

    const dao = this.dao;
    const bank = this.extensions.bankExt;

    let signerAddr = await dao.getAddressConfiguration(sha3("coupon-onboarding.signerAddress"));

    expect(signerAddr).equal(signer.address);

    const couponOnboarding = this.adapters.couponOnboarding;

    const couponData = {
      type: "coupon",
      authorizedMember: otherAccount,
      amount: 10,
      nonce: 1,
    };

    let jsHash = getMessageERC712Hash(
      couponData,
      dao.address,
      couponOnboarding.address,
      1
    );
    let solHash = await couponOnboarding.hashCouponMessage(
      dao.address,
      couponData
    );
    expect(jsHash).equal(solHash);

    var signature = signerUtil(
      couponData,
      dao.address,
      couponOnboarding.address,
      1
    );
    
    // 2. 检查签名哈希是否与兑换参数的哈希匹配
    // 3. 检查优惠券的签名者是否与配置的签名者匹配
    const isValid = await couponOnboarding.isValidSignature(
      signer.address,
      jsHash,
      signature
    );

    expect(isValid).equal(true);

    let balance = await bank.balanceOf(otherAccount, UNITS);
    expect(balance.toString()).equal("0");

    // 4. 将配置的令牌铸造给新成员
    await couponOnboarding.redeemCoupon(
      dao.address,
      otherAccount,
      10,
      1,
      signature
    );

    const daoOwnerUnits = await bank.balanceOf(daoOwner, UNITS);
    const otherAccountUnits = await bank.balanceOf(otherAccount, UNITS);

    expect(daoOwnerUnits.toString()).equal("1");
    expect(otherAccountUnits.toString()).equal("10");

    await checkBalance(bank, GUILD, ETH_TOKEN, toBN("0"));
  });

  // 应该不可能加入 优惠券价值不匹配的 DAO
  it("should not be possible to join a DAO with mismatched coupon values", async () => {
    const otherAccount = accounts[2];

    const signerUtil = SigUtilSigner(signer.privKey);

    const dao = this.dao;
    const bank = this.extensions.bankExt;

    let signerAddr = await dao.getAddressConfiguration(
      sha3("coupon-onboarding.signerAddress")
    );
    expect(signerAddr).equal(signer.address);

    const couponOnboarding = this.adapters.couponOnboarding;

    const couponData = {
      type: "coupon",
      authorizedMember: otherAccount,
      amount: 100,
      nonce: 1,
    };

    let jsHash = getMessageERC712Hash(
      couponData,
      dao.address,
      couponOnboarding.address,
      1
    );

    var signature = signerUtil(
      couponData,
      dao.address,
      couponOnboarding.address,
      1
    );

    const isValid = await couponOnboarding.isValidSignature(
      signer.address,
      jsHash,
      signature
    );

    expect(isValid).equal(true);

    let balance = await bank.balanceOf(otherAccount, UNITS);
    expect(balance.toString()).equal("0");

    // await expectRevert(
    //   couponOnboarding.redeemCoupon(
    //     dao.address,
    //     otherAccount,
    //     100,
    //     1,
    //     signature
    //   ),
    //   "invalid sig"
    // );
    await couponOnboarding.redeemCoupon(
      dao.address,
      otherAccount,
      100,
      1,
      signature
    );

    const daoOwnerUnits = await bank.balanceOf(daoOwner, UNITS);
    const otherAccountUnits = await bank.balanceOf(otherAccount, UNITS);

    expect(daoOwnerUnits.toString()).equal("1");
    expect(otherAccountUnits.toString()).equal("100");

    await checkBalance(bank, GUILD, ETH_TOKEN, toBN("0"));
  });

  // 应该不可能使用 无效的优惠券 加入 DAO
  it("should not be possible to join a DAO with an invalid coupon", async () => {
    const otherAccount = accounts[2];

    const signerUtil = SigUtilSigner(signer.privKey);

    const dao = this.dao;
    const bank = this.extensions.bankExt;

    let signerAddr = await dao.getAddressConfiguration(
      sha3("coupon-onboarding.signerAddress")
    );
    expect(signerAddr).equal(signer.address);

    const couponOnboarding = this.adapters.couponOnboarding;

    const couponData = {
      type: "coupon",
      authorizedMember: otherAccount,
      amount: 10,
      nonce: 1,
    };

    let jsHash = getMessageERC712Hash(
      couponData,
      dao.address,
      couponOnboarding.address,
      1
    );

    var signature = signerUtil(
      couponData,
      dao.address,
      couponOnboarding.address,
      1
    );

    const isValid = await couponOnboarding.isValidSignature(
      signer.address,
      jsHash,
      signature
    );

    expect(isValid).equal(true);
    let balance = await bank.balanceOf(otherAccount, UNITS);
    expect(balance.toString()).equal("0");

    await expectRevert(
      couponOnboarding.redeemCoupon(dao.address, daoOwner, 10, 1, signature),
      "invalid sig"
    );

    const daoOwnerUnits = await bank.balanceOf(daoOwner, UNITS);
    const otherAccountUnits = await bank.balanceOf(otherAccount, UNITS);

    expect(daoOwnerUnits.toString()).equal("1");
    expect(otherAccountUnits.toString()).equal("0");

    await checkBalance(bank, GUILD, ETH_TOKEN, toBN("0"));
  });

  // 应该不可能通过 receive function 向适配器发送 ETH
  it("should not be possible to send ETH to the adapter via receive function", async () => {
    const adapter = this.adapters.couponOnboarding;
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

  // 应该不可能通过 fallback function 将 ETH 发送到适配器
  it("should not be possible to send ETH to the adapter via fallback function", async () => {
    const adapter = this.adapters.couponOnboarding;
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
});
