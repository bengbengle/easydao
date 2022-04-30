// Whole-script strict mode syntax
"use strict";

const {
  ETH_TOKEN,
  toBN,
  sha3,
  toWei,
  fromAscii,
} = require("../../utils/contract-util");

const {
  deployDefaultDao,
  takeChainSnapshot,
  revertChainSnapshot,
  accounts,
  expectRevert,
  expect,
  BankFactory,
  web3,
} = require("../../utils/oz-util");

describe("Extension - Bank", () => {
  const daoOwner = accounts[0];

  before("deploy dao", async () => {
    const { dao, adapters, extensions } = await deployDefaultDao({
      owner: daoOwner,
    });
    this.dao = dao;
    this.adapters = adapters;
    this.extensions = extensions;
  });

  beforeEach(async () => {
    this.snapshotId = await takeChainSnapshot();
  });

  afterEach(async () => {
    await revertChainSnapshot(this.snapshotId);
  });

  it("should be possible to create a dao with a bank extension pre-configured", async () => {
    const dao = this.dao;
    const bankAddress = await dao.getExtensionAddress(sha3("bank"));
    expect(bankAddress).to.not.be.null;
  });

  it("should be possible to get all the tokens registered in the bank", async () => {
    const bank = this.extensions.bankExt;
    const tokens = await bank.getTokens();
    expect(tokens.toString()).equal([ETH_TOKEN].toString());
  });

  it("should be possible to get a registered token using the token index", async () => {
    const bank = this.extensions.bankExt;
    const token = await bank.getToken(0);
    expect(token.toString()).equal(ETH_TOKEN.toString());
  });

  it("should be possible to get the total amount of tokens registered in the bank", async () => {
    const bank = this.extensions.bankExt;
    const totalTokens = await bank.nbTokens();
    expect(totalTokens.toString()).equal("1");
  });

  it("should not be possible to create a bank that supports more than 200 external tokens", async () => {
    const maxExternalTokens = 201;
    const identityBank = this.extensions.bankExt;
    const bankFactory = await BankFactory.new(identityBank.address);
    await expectRevert(
      bankFactory.create(this.dao.address, maxExternalTokens),
      "max number of external tokens should be (0,200)"
    );
  });

  it("should not be possible to create a bank that supports 0 external tokens", async () => {
    const maxExternalTokens = 0;
    const identityBank = this.extensions.bankExt;
    const bankFactory = await BankFactory.new(identityBank.address);
    await expectRevert(
      bankFactory.create(this.dao.address, maxExternalTokens),
      "max number of external tokens should be (0,200)"
    );
  });

  it("should not be possible to set the max external tokens if bank is already initialized", async () => {
    const bank = this.extensions.bankExt;
    await expectRevert(
      bank.setMaxExternalTokens(10),
      "bank already initialized"
    );
  });

  it("should not be possible to send ETH to the adapter via receive function", async () => {
    const adapter = this.adapters.bankAdapter;
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
    const adapter = this.adapters.bankAdapter;
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
