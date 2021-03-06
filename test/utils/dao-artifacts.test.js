// Whole-script strict mode syntax
"use strict";

const expectEvent = require("@openzeppelin/test-helpers/src/expectEvent");
const expectRevert = require("@openzeppelin/test-helpers/src/expectRevert");
const { sha3, toBN } = require("../../utils/contract-util");
const { accounts, expect, DaoArtifacts } = require("../../utils/oz-util");
const { ContractType } = require("../../configs/contracts.config");

describe("Utils - DaoArtifacts", () => {
  it("should be possible to create a dao artifacts contract", async () => {
    const daoArtifacts = await DaoArtifacts.new();
    expect(daoArtifacts.address).to.not.be.null;
    expect(daoArtifacts.address).to.not.be.equal(
      "0x0000000000000000000000000000000000000000"
    );
  });

  // 应该可以将新适配器添加到 dao 工件存储
  it("should be possible add a new adapter to the dao artifacts storage", async () => {
    const daoArtifacts = await DaoArtifacts.new();
    const owner = accounts[2];
    const adapterAddress = accounts[9];
    const res = await daoArtifacts.addArtifact(
      sha3("adapter1"),
      sha3("v1.0.0"),
      adapterAddress,
      ContractType.Adapter,
      { from: owner }
    );
    expectEvent(res, "NewArtifact", {
      _id: sha3("adapter1"),
      _owner: owner,
      _version: sha3("v1.0.0"),
      _address: adapterAddress,
      _type: "3",
    });
  });

  // 应该可以从 dao 工件存储中获取适配器地址
  it("should be possible get the adapter address from the dao artifacts storage", async () => {
    const daoArtifacts = await DaoArtifacts.new();
    const owner = accounts[2];
    const adapterAddress = accounts[9];

    await daoArtifacts.addArtifact(
      sha3("adapter1"),
      sha3("v1.0.0"),
      adapterAddress,
      ContractType.Adapter,
      { from: owner }
    );

    const address = await daoArtifacts.getArtifactAddress(
      sha3("adapter1"),
      owner,
      sha3("v1.0.0"),
      ContractType.Adapter
    );
    expect(address).to.be.equal(adapterAddress);
  });

  // 应该可以在 dao 工件 存储中 添加一个新的 扩展工厂
  it("should be possible add a new extension factory to the dao artifacts storage", async () => {
    const daoArtifacts = await DaoArtifacts.new();
    const owner = accounts[2];
    const extensionAddress = accounts[9];
    const res = await daoArtifacts.addArtifact(
      sha3("extFactory1"),
      sha3("v1.0.0"),
      extensionAddress,
      ContractType.Factory,
      { from: owner }
    );
    expectEvent(res, "NewArtifact", {
      _id: sha3("extFactory1"),
      _owner: owner,
      _version: sha3("v1.0.0"),
      _address: extensionAddress,
      _type: "1",
    });
  });

  // 应该可以从 dao 工件存储中获取扩展工厂地址
  it("should be possible get the extension factory address from the dao artifacts storage", async () => {
    const daoArtifacts = await DaoArtifacts.new();
    const owner = accounts[2];
    const extensionAddress = accounts[9];
    await daoArtifacts.addArtifact(
      sha3("extFactory2"),
      sha3("v1.0.0"),
      extensionAddress,
      ContractType.Factory,
      { from: owner }
    );

    const address = await daoArtifacts.getArtifactAddress(
      sha3("extFactory2"),
      owner,
      sha3("v1.0.0"),
      ContractType.Factory
    );
    expect(address).to.be.equal(extensionAddress);
  });

  // 应该可以执行批量更新
  it("should be possible to execute a batch update", async () => {
    const owner = accounts[2];
    const daoArtifacts = await DaoArtifacts.new({ from: owner });
    await daoArtifacts.updateArtifacts(
      [
        {
          _id: sha3("adapter1"),
          _owner: owner,
          _version: sha3("v1.0.0"),
          _address: accounts[4],
          _type: ContractType.Adapter,
        },
        {
          _id: sha3("extFactory2"),
          _owner: owner,
          _version: sha3("v1.0.0"),
          _address: accounts[5],
          _type: ContractType.Factory,
        },
      ],
      { from: owner }
    );

    expect(
      await daoArtifacts.getArtifactAddress(
        sha3("adapter1"),
        owner,
        sha3("v1.0.0"),
        ContractType.Adapter
      )
    ).to.be.equal(accounts[4]);

    expect(
      await daoArtifacts.getArtifactAddress(
        sha3("extFactory2"),
        owner,
        sha3("v1.0.0"),
        ContractType.Factory
      )
    ).to.be.equal(accounts[5]);
  });

  // 如果您不是所有者，则应该无法执行批量更新
  it("should not be possible to execute a batch update if you are not the owner", async () => {
    const owner = accounts[2];
    const anotherUser = accounts[3];
    const daoArtifacts = await DaoArtifacts.new({ from: owner });
    await expectRevert(
      daoArtifacts.updateArtifacts(
        [
          {
            _id: sha3("adapter1"),
            _owner: owner,
            _version: sha3("v1.0.0"),
            _address: accounts[4],
            _type: ContractType.Adapter,
          },
          {
            _id: sha3("extFactory2"),
            _owner: owner,
            _version: sha3("v1.0.0"),
            _address: accounts[5],
            _type: ContractType.Factory,
          },
        ],
        { from: anotherUser }
      ),
      "Ownable: caller is not the owner."
    );
  });

  // 应该可以使用多达 20 个工件执行批量更新
  it("should be possible to execute a batch update with up to 20 artifacts", async () => {
    const owner = accounts[2];
    const daoArtifacts = await DaoArtifacts.new({ from: owner });
    let artifacts = [];
    for (let i = 0; i < 20; i++) {
      artifacts.push({
        _id: sha3(`adapter:${i + 1}`),
        _owner: owner,
        _version: sha3("v1.0.0"),
        _address: owner,
        _type: ContractType.Adapter,
      });
    }

    daoArtifacts.updateArtifacts(artifacts, { from: owner });
  });

  // 应该不可能执行超过 20 个工件的批量更新
  it("should not be possible to execute a batch update with more than 20 artifacts", async () => {
    const owner = accounts[2];
    const daoArtifacts = await DaoArtifacts.new({ from: owner });
    let artifacts = [];
    for (let i = 0; i < 21; i++) {
      artifacts.push({
        _id: sha3(`adapter:${i + 1}`),
        _owner: owner,
        _version: sha3("v1.0.0"),
        _address: owner,
        _type: ContractType.Adapter,
      });
    }

    await expectRevert(
      daoArtifacts.updateArtifacts(artifacts, { from: owner }),
      "Maximum artifacts limit exceeded"
    );
  });
});
