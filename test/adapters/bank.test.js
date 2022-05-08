// Whole-script strict mode syntax
"use strict";

const {
  toBN,
  toWei,
  fromUtf8,
  fromAscii,
  unitPrice,
  UNITS,
  GUILD,
  ETH_TOKEN,
} = require("../../utils/contract-util");

const {
  deployDefaultDao,
  takeChainSnapshot,
  revertChainSnapshot,
  proposalIdGenerator,
  advanceTime,
  accounts,
  expect,
  expectRevert,
  web3,
  getBalance,
} = require("../../utils/oz-util");

const { checkBalance } = require("../../utils/test-util");

const remaining = unitPrice.sub(toBN("50000000000000"));
const daoOwner = accounts[1];
const applicant = accounts[2];
const newMember = accounts[3];
const expectedGuildBalance = toBN("1200000000000000000");
const proposalCounter = proposalIdGenerator().generator;

function getProposalCounter() {
  return proposalCounter().next().value;
}

describe("Adapter - Bank", () => {
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

  it("should be possible to withdraw funds from the bank", async () => {
    const bank = this.extensions.bankExt;
    const voting = this.adapters.voting;
    const financing = this.adapters.financing;
    const onboarding = this.adapters.onboarding;
    const bankAdapter = this.adapters.bankAdapter;

    let proposalId = getProposalCounter();

    // Add funds to the Guild Bank after sponsoring a member to join the Guild
    // 赞助会员加入公会后向 公会银行 充值
    await onboarding.submitProposal(
      this.dao.address,
      proposalId,
      newMember,
      UNITS,
      unitPrice.mul(toBN(10)).add(remaining),
      [],
      {
        from: daoOwner,
        gasPrice: toBN("0"),
      }
    );

    await voting.submitVote(this.dao.address, proposalId, 1, {
      from: daoOwner,
      gasPrice: toBN("0"),
    });
    // should not be able to process before the voting period has ended
    // 在投票期结束之前无法处理
    await expectRevert(
      onboarding.processProposal(this.dao.address, proposalId, {
        from: daoOwner,
        value: unitPrice.mul(toBN(10)).add(remaining),
        gasPrice: toBN("0"),
      }),
      "proposal has not been voted on yet"
    );

    await advanceTime(10000);
    await onboarding.processProposal(this.dao.address, proposalId, {
      from: daoOwner,
      value: unitPrice.mul(toBN(10)).add(remaining),
      gasPrice: toBN("0"),
    });
    // Check Guild Bank Balance
    // 检查公会银行余额
    await checkBalance(bank, GUILD, ETH_TOKEN, expectedGuildBalance);

    // Create Financing Request
    // 创建融资请求
    let requestedAmount = toBN(50000);
    proposalId = getProposalCounter();

    await financing.submitProposal(
      this.dao.address,
      proposalId,
      applicant,
      ETH_TOKEN,
      requestedAmount,
      fromUtf8(""),
      { from: daoOwner, gasPrice: toBN("0") }
    );

    //Member votes on the Financing proposal
    // 成员对融资提案进行投票
    await voting.submitVote(this.dao.address, proposalId, 1, {
      from: daoOwner,
      gasPrice: toBN("0"),
    });

    //Check applicant balance before Financing proposal is processed
    // 在处理融资建议之前检查申请人余额
    await checkBalance(bank, applicant, ETH_TOKEN, "0");

    //Process Financing proposal after voting
    // 投票后处理融资提案
    await advanceTime(10000);
    await financing.processProposal(this.dao.address, proposalId, {
      from: daoOwner,
      gasPrice: toBN("0"),
    });

    //Check Guild Bank balance to make sure the transfer has happened
    // 检查公会银行 余额以确保转账已经发生
    await checkBalance(
      bank,
      GUILD,
      ETH_TOKEN,
      expectedGuildBalance.sub(requestedAmount)
    );
    //Check the applicant token balance to make sure the funds are available in the bank for the applicant account
    // 检查申请者代币余额，确保申请者账户的资金在银行可用
    await checkBalance(bank, applicant, ETH_TOKEN, requestedAmount);

    const ethBalance = await getBalance(applicant);
    // Withdraw the funds from the bank
    // 从银行提取资金
    await bankAdapter.withdraw(this.dao.address, applicant, ETH_TOKEN, {
      from: daoOwner,
      gasPrice: toBN("0"),
    });
    await checkBalance(bank, applicant, ETH_TOKEN, 0);
    const ethBalance2 = await getBalance(applicant);
    expect(ethBalance.add(requestedAmount).toString()).equal(
      ethBalance2.toString()
    );
  });

  it("should possible to send eth to the dao bank", async () => {
    const bank = this.extensions.bankExt;
    const bankAdapter = this.adapters.bankAdapter;

    await checkBalance(bank, GUILD, ETH_TOKEN, "0");

    await bankAdapter.sendEth(this.dao.address, { value: toWei("5") });

    await checkBalance(bank, GUILD, ETH_TOKEN, toWei("5"));
  });

  it("should not be possible to send ETH to the adapter via receive function", async () => {
    const bankAdapter = this.adapters.bankAdapter;
    await expectRevert(
      web3.eth.sendTransaction({
        to: bankAdapter.address,
        from: daoOwner,
        gasPrice: toBN("0"),
        value: toWei("1"),
      }),
      "revert"
    );
  });

  it("should not be possible to send ETH to the adapter via fallback function", async () => {
    const bankAdapter = this.adapters.bankAdapter;
    await expectRevert(
      web3.eth.sendTransaction({
        to: bankAdapter.address,
        from: daoOwner,
        gasPrice: toBN("0"),
        value: toWei("1"),
        data: fromAscii("should go to fallback func"),
      }),
      "revert"
    );
  });
});
