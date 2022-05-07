// Whole-script strict mode syntax
"use strict";

const { toBN } = require("../../utils/contract-util");

const { cloneDao } = require("../../utils/deployment-util");

const {
  accounts,
  expect,
  DaoRegistry,
  DaoFactory,
  deployFunction,
  attachFunction,
} = require("../../utils/oz-util");

describe("Core - DaoFactory", () => {
  const owner = accounts[1];
  const anotherOwner = accounts[2];

  const createIdentityDao = () => {
    return DaoRegistry.new({
      from: owner,
      gasPrice: toBN("0"),
    });
  };

  it("should be possible create an identity dao and clone it", async () => {
    const identityDao = await createIdentityDao();

    const { daoName } = await cloneDao({
      identityDao,
      owner: anotherOwner,
      name: "cloned-dao",
      DaoRegistry,
      DaoFactory,
      deployFunction,
      attachFunction,
    });

    expect(daoName).equal("cloned-dao");
  });

  it("should be possible to get a DAO address by its name if it was created by the factory", async () => {
    const identityDao = await createIdentityDao();

    const { daoFactory, dao } = await cloneDao({
      identityDao,
      owner: anotherOwner,
      name: "new-dao",
      DaoRegistry,
      DaoFactory,
      deployFunction,
      attachFunction,
    });

    const retrievedAddress = await daoFactory.getDaoAddress("new-dao", {
      from: anotherOwner,
      gasPrice: toBN("0"),
    });
    expect(retrievedAddress).equal(dao.address);
  });

  it("should not be possible to get a DAO address of it was not created by the factory", async () => {
    const identityDao = await createIdentityDao();

    const { daoFactory } = await cloneDao({
      identityDao,
      owner: anotherOwner,
      name: "new-dao",
      DaoRegistry,
      DaoFactory,
      deployFunction,
      attachFunction,
    });

    let retrievedAddress = await daoFactory.getDaoAddress("random-dao", {
      from: anotherOwner,
      gasPrice: toBN("0"),
    });

    expect(retrievedAddress).equal(
      "0x0000000000000000000000000000000000000000"
    );
  });
});
