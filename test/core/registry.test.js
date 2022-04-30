// Whole-script strict mode syntax
"use strict";



const {
  toWei,
  toBN,
  fromAscii,
  fromUtf8,
  ETH_TOKEN,
} = require("../../utils/contract-util");

const {
  expectRevert,
  expect,
  DaoRegistry,
  web3,
  accounts,
} = require("../../utils/oz-util");

describe("Core - Registry", () => {
  it("should not be possible to add a module with invalid id", async () => {
    let moduleId = fromUtf8("");
    let moduleAddress = "0x627306090abaB3A6e1400e9345bC60c78a8BEf57";
    let registry = await DaoRegistry.new();
    await expectRevert(
      registry.replaceAdapter(moduleId, moduleAddress, 0, [], []),
      "adapterId must not be empty"
    );
  });

  it("should not be possible to add an adapter with invalid id", async () => {
    let adapterId = fromUtf8("");
    let adapterAddr = "0x627306090abaB3A6e1400e9345bC60c78a8BEf57";
    let registry = await DaoRegistry.new();
    await expectRevert(
      registry.replaceAdapter(adapterId, adapterAddr, 0, [], []),
      "adapterId must not be empty"
    );
  });

  it("should not be possible to add an adapter with invalid address]", async () => {
    let adapterId = fromUtf8("1");
    let adapterAddr = "";
    let registry = await DaoRegistry.new();
    await expectRevert(
      registry.replaceAdapter(adapterId, adapterAddr, 0, [], []),
      "invalid address"
    );
  });

  it("should be possible to replace an adapter when the id is already in use", async () => {
    let adapterId = fromUtf8("1");
    let adapterAddr = "0x627306090abaB3A6e1400e9345bC60c78a8BEf57";
    let newAdapterAddr = "0xd7bCe30D77DE56E3D21AEfe7ad144b3134438F5B";
    let registry = await DaoRegistry.new();
    //Add a module with id 1
    await registry.replaceAdapter(adapterId, adapterAddr, 0, [], []);
    await registry.replaceAdapter(adapterId, newAdapterAddr, 0, [], []);
    let address = await registry.getAdapterAddress(adapterId);
    expect(address).equal(newAdapterAddr);
  });

  it("should be possible to add an adapter with a valid id and address", async () => {
    let adapterId = fromUtf8("1");
    let adapterAddr = "0x627306090abaB3A6e1400e9345bC60c78a8BEf57";
    let registry = await DaoRegistry.new();
    await registry.replaceAdapter(adapterId, adapterAddr, 0, [], []);
    let address = await registry.getAdapterAddress(adapterId);
    expect(address).equal(adapterAddr);
  });

  it("should be possible to remove an adapter", async () => {
    let adapterId = fromUtf8("2");
    let adapterAddr = "0x627306090abaB3A6e1400e9345bC60c78a8BEf57";
    let registry = await DaoRegistry.new();
    await registry.replaceAdapter(adapterId, adapterAddr, 0, [], []);
    let address = await registry.getAdapterAddress(adapterId);
    expect(address).equal(adapterAddr);
    await registry.replaceAdapter(adapterId, ETH_TOKEN, 0, [], []);
    await expectRevert(
      registry.getAdapterAddress(adapterId),
      "adapter not found"
    );
  });

  it("should not be possible to remove an adapter with an empty id", async () => {
    let adapterId = fromUtf8("");
    let registry = await DaoRegistry.new();
    await expectRevert(
      registry.replaceAdapter(adapterId, ETH_TOKEN, 0, [], []),
      "adapterId must not be empty"
    );
  });

  it("should not be possible for a zero address to be considered a member", async () => {
    let registry = await DaoRegistry.new();
    let isMember = await registry.isMember(
      "0x0000000000000000000000000000000000000000"
    );
    expect(isMember).equal(false);
  });

  it("should not be possible to send ETH to the DaoRegistry via receive function", async () => {
    let registry = await DaoRegistry.new();
    await expectRevert(
      web3.eth.sendTransaction({
        to: registry.address,
        from: accounts[0],
        gasPrice: toBN("0"),
        value: toWei("1"),
      }),
      "revert"
    );
  });

  it("should not be possible to send ETH to the DaoRegistry via fallback function", async () => {
    let registry = await DaoRegistry.new();
    await expectRevert(
      web3.eth.sendTransaction({
        to: registry.address,
        from: accounts[0],
        gasPrice: toBN("0"),
        value: toWei("1"),
        data: fromAscii("should go to fallback func"),
      }),
      "revert"
    );
  });
});
