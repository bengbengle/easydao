// Whole-script strict mode syntax
"use strict";

const expectEvent = require("@openzeppelin/test-helpers/src/expectEvent");
const { sha3, toBN, toWei } = require("../../utils/contract-util");

const {
  deployDefaultDao,
  ERC20MinterContract,
  ProxTokenContract,
  accounts,
  web3,
  expect,
  expectRevert,
} = require("../../utils/oz-util");

const {
  executorExtensionAclFlagsMap,
  entryDao,
  entryExecutor,
} = require("../../utils/access-control-util");

const { extensionsIdsMap } = require("../../utils/dao-ids-util");

describe("Extension - Executor", () => {
  const daoOwner = accounts[0];

  // 应该可以创建一个 预先配置了 执行器扩展的 dao
  it("should be possible to create a dao with an executor extension pre-configured", async () => {
    const { dao } = await deployDefaultDao({
      owner: daoOwner,
    });
    const executorAddress = await dao.getExtensionAddress(sha3("executor-ext"));
    expect(executorAddress).to.not.be.null;
  });

  // 应该可以通过 执行器扩展 使用 委托调用 来铸造代币
  it("should be possible to mint tokens using a delegated call via executor extension", async () => {
    const { dao, factories, extensions } = await deployDefaultDao({
      owner: daoOwner,
      finalize: false,
    });

    const erc20Minter = await ERC20MinterContract.new();
    const executorExt = extensions.executorExt;

    await factories.daoFactory.addAdapters(
      dao.address,
      [
        entryDao("erc20Minter", erc20Minter.address, {
          dao: [],
          extensions: {},
        }),
      ],
      { from: daoOwner }
    );

    await factories.daoFactory.configureExtension(
      dao.address,
      executorExt.address,
      [
        entryExecutor(erc20Minter.address, {
          extensions: {
            [extensionsIdsMap.EXECUTOR_EXT]: [
              executorExtensionAclFlagsMap.EXECUTE,
            ],
          },
        }),
      ],
      { from: daoOwner }
    );

    await dao.finalizeDao({ from: daoOwner });

    const minterAddress = await dao.getAdapterAddress(sha3("erc20Minter"));
    expect(minterAddress).to.not.be.null;

    const proxToken = await ProxTokenContract.new();
    expect(proxToken).to.not.be.null;

    const res = await erc20Minter.execute(
      dao.address,
      proxToken.address,
      toBN("10000"),
      { from: daoOwner }
    );

    // 适配器应通过代理 调用自身 并生成令牌
    // The adapter should call itself via proxy and mint the token
    expectEvent(res.receipt, "Minted", { owner: erc20Minter.address, amount: "10000" });

    // 令牌铸币调用应该从适配器触发，但发送者实际上是代理执行者
    const pastEvents = await proxToken.getPastEvents();
    const event = pastEvents[1];
    const { owner, amount } = pastEvents[1].returnValues;
    expect(event.event).to.be.equal("MintedProxToken");
    expect(owner).to.be.equal(executorExt.address);
    expect(amount).to.be.equal("10000");
  });

  // 没有 ACL 权限应该不能执行委托调用
  it("should not be possible to execute a delegate call without the ACL permission", async () => {
    const { dao, factories, extensions } = await deployDefaultDao({
      owner: daoOwner,
      finalize: false,
    });

    const erc20Minter = await ERC20MinterContract.new();
    const executorExt = extensions.executorExt;

    await factories.daoFactory.addAdapters(
      dao.address,
      [
        entryDao("erc20Minter", erc20Minter.address, {
          dao: [],
          extensions: {},
        }),
      ],
      { from: daoOwner }
    );

    await factories.daoFactory.configureExtension(
      dao.address,
      executorExt.address,
      [
        entryExecutor(erc20Minter.address, {
          dao: [], // no access granted
          extensions: {}, // no access granted
        }),
      ],
      { from: daoOwner }
    );

    await dao.finalizeDao({ from: daoOwner });

    const minterAddress = await dao.getAdapterAddress(sha3("erc20Minter"));
    expect(minterAddress).to.not.be.null;

    const proxToken = await ProxTokenContract.new();
    expect(proxToken).to.not.be.null;

    await expectRevert(
      erc20Minter.execute(dao.address, proxToken.address, toBN("10000"), {
        from: daoOwner,
      }),
      "executorExt::accessDenied"
    );
  });
  
  // 在没有 ACL 权限的情况下，应该不可能向扩展发送 ETH
  it("should not be possible to send ETH to the extension without the ACL permission", async () => {
    const { dao, extensions } = await deployDefaultDao({
      owner: daoOwner,
      finalize: false,
    });

    const executorExt = extensions.executorExt;

    await dao.finalizeDao({ from: daoOwner });

    await expectRevert(
      web3.eth.sendTransaction({
        to: executorExt.address,
        from: daoOwner,
        gasPrice: toBN("0"),
        value: toWei("1"),
      }),
      "executorExt::accessDenied"
    );
  });
});
