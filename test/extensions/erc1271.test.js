// Whole-script strict mode syntax
"use strict";

const { sha3, soliditySha3 } = require("../../utils/contract-util");

const {
  deployDefaultDao,
  takeChainSnapshot,
  revertChainSnapshot,
  expectRevert,
  accounts,
  expect,
} = require("../../utils/oz-util");

const arbitrarySignature =
  "0xc531a1d9046945d3732c73d049da2810470c3b0663788dca9e9f329a35c8a0d56add77ed5ea610b36140641860d13849abab295ca46c350f50731843c6517eee1c";
const arbitrarySignatureHash = soliditySha3({
  t: "bytes",
  v: arbitrarySignature,
});
const arbitraryMsgHash =
  "0xec4870a1ebdcfbc1cc84b0f5a30aac48ed8f17973e0189abdb939502e1948238";
const magicValue = "0x1626ba7e";

describe("Extension - ERC1271", () => {
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

  it("should be possible to create a dao with an erc1271 extension pre-configured", async () => {
    const dao = this.dao;
    const erc1271Address = await dao.getExtensionAddress(sha3("erc1271"));
    expect(erc1271Address).to.not.be.null;
  });

  it("should not be possible to submit a signature without the SIGN permission", async () => {
    const erc1271Extension = this.extensions.erc1271Ext;
    await expectRevert(
      erc1271Extension.sign(
        this.dao.address,
        arbitraryMsgHash,
        arbitrarySignatureHash,
        magicValue
      ),
      "erc1271::accessDenied"
    );
  });

  it("should revert for invalid signatures", async () => {
    const erc1271Extension = this.extensions.erc1271Ext;
    await expectRevert(
      erc1271Extension.isValidSignature(arbitraryMsgHash, arbitrarySignature),
      "erc1271::invalid signature"
    );
  });
});
