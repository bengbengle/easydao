// Whole-script strict mode syntax
"use strict";


const { toWei } = require("../../utils/contract-util");

const {
  TestFairShareCalc,
  expect,
  expectRevert,
} = require("../../utils/oz-util");

describe("Helper - FairShareHelper", () => {
  it("should calculate the fair unit if the given parameters are valid", async () => {
    const fairShareCalc = await TestFairShareCalc.new();
    const balance = toWei("4.3");
    const units = toWei("100");
    const totalUnits = toWei("1000");
    const fairShare = await fairShareCalc.calculate(balance, units, totalUnits);
    // It should return 43% of the units based on the balance
    expect(fairShare.toString() / 10 ** 18).equal(0.43);
  });

  it("should revert when the totalUnits parameter is.toEqual to zero", async () => {
    const fairShareCalc = await TestFairShareCalc.new();
    const balance = toWei("4.3");
    const units = toWei("100");
    const totalUnits = toWei("0");
    await expectRevert(
      fairShareCalc.calculate(balance, units, totalUnits),
      "revert totalUnits must be greater than 0"
    );
  });

  it("should revert when the units is greater than the totalUnits", async () => {
    const fairShareCalc = await TestFairShareCalc.new();
    const balance = toWei("4.3");
    const units = toWei("100");
    const totalUnits = toWei("10");
    await expectRevert(
      fairShareCalc.calculate(balance, units, totalUnits),
      "revert units must be less than or equal to totalUnits"
    );
  });

  it("should return 100% of the units if the member holds all the units of the dao", async () => {
    const fairShareCalc = await TestFairShareCalc.new();
    const balance = toWei("1");
    const units = toWei("100");
    const totalUnits = toWei("100");
    const fairShare = await fairShareCalc.calculate(balance, units, totalUnits);
    // It should return 100% of the units based on the balance
    expect(fairShare.toString() / 10 ** 18).equal(1.0);
  });
});
