// Whole-script strict mode syntax
"use strict";

const {
  toBN,
  GUILD,
  unitPrice,
  remaining,
  LOOT,
} = require("../../utils/contract-util");

const {
  deployDefaultDao,
  proposalIdGenerator,
  advanceTime,
  accounts,
  expect,
  expectRevert,
  OLToken,
} = require("../../utils/oz-util");

const daoOwner = accounts[1];
const proposalCounter = proposalIdGenerator().generator;

function getProposalCounter() {
  return proposalCounter().next().value;
}

describe("Adapter - Non Voting Onboarding", () => {
  // 质押原始 ETH 的同时请求 Loot 作为成员加入 DAO
  it("should be possible to join a DAO as a member without any voting power by requesting Loot while staking raw ETH", async () => {
    const advisorAccount = accounts[2];

    const { dao, adapters, extensions } = await deployDefaultDao({owner: daoOwner});
    const bank = extensions.bankExt;
    const onboarding = adapters.onboarding;
    const voting = adapters.voting;

    // 为了获得 loot 发送给 DAO 的 ETH 总量
    let ethAmount = unitPrice.mul(toBN(3)).add(remaining);
    let proposalId = "0x1";

    // 请求以顾问身份加入 DAO（无投票权），仅发送带有 RAW ETH 的 tx 并指定 nonVotingOnboarding
    await onboarding.submitProposal(
      dao.address,
      proposalId,
      advisorAccount,
      LOOT,
      ethAmount,
      [],
      {
        from: daoOwner,
        gasPrice: toBN("0"),
      }
    );

    // 对接受新顾问的新提案进行投票
    await voting.submitVote(dao.address, proposalId, 1, {from: daoOwner, gasPrice: toBN("0")});

    // Process the new proposal
    await advanceTime(10000);
    await onboarding.processProposal(dao.address, proposalId, {
      from: daoOwner,
      value: ethAmount,
      gasPrice: toBN("0"),
    });

    // Check the number of Loot (non-voting units) issued to the new Avisor
    const advisorAccountLoot = await bank.balanceOf(advisorAccount, LOOT);
    expect(advisorAccountLoot.toString()).equal("3000000000000000");

    // Guild balance must not change when Loot units are issued
    const guildBalance = await bank.balanceOf(
      GUILD,
      "0x0000000000000000000000000000000000000000"
    );
    expect(guildBalance.toString()).equal("360000000000000000");
  });

  // 质押 ERC20 代币的同时请求 Loot 作为成员加入 DAO
  it("should be possible to join a DAO as a member without any voting power by requesting Loot while staking ERC20 token", async () => {
    const advisorAccount = accounts[2];

    // Issue OpenLaw ERC20 Basic Token for tests
    const tokenSupply = 1000000;
    const oltContract = await OLToken.new(tokenSupply);
    const lootUnitPrice = 10;
    const nbOfLootUnits = 100000000;

    const { dao, adapters, extensions } = await deployDefaultDao({
      owner: daoOwner,
      unitPrice: lootUnitPrice,
      nbUnits: nbOfLootUnits,
      tokenAddr: oltContract.address,
    });

    const bank = extensions.bankExt;
    const onboarding = adapters.onboarding;
    const voting = adapters.voting;

    // 将 1000 OLT 转入顾问账户 Transfer 1000 OLTs to the Advisor account
    await oltContract.transfer(advisorAccount, 100);
    
    const advisorTokenBalance = await oltContract.balanceOf.call(advisorAccount);

    expect(advisorTokenBalance.toString()).equal("100");

    // 发送到 DAO 的 OLT 总数
    const tokenAmount = 10;

    // tx 传递 OLT ERC20 代币、金额和处理提案的 nonVotingOnboarding 适配器
    const proposalId = getProposalCounter();
    // await expectRevert.unspecified(
    //   onboarding.submitProposal(
    //     dao.address,
    //     proposalId,
    //     advisorAccount,
    //     LOOT,
    //     tokenAmount,
    //     [],
    //     {
    //       from: advisorAccount,
    //       gasPrice: toBN("0"),
    //     }
    //   )
    // );

    // Pre-approve spender (onboarding adapter) to transfer proposer tokens
    // 预先批准 spender（入职适配器）以转移令牌
    await oltContract.approve(onboarding.address, tokenAmount, {from: advisorAccount});

    await onboarding.submitProposal(
      dao.address,
      proposalId,
      advisorAccount,
      LOOT,
      tokenAmount,
      [],
      {
        from: daoOwner,
        gasPrice: toBN("0"),
      }
    );

    // 对接受新顾问的新提案进行投票
    await voting.submitVote(dao.address, proposalId, 1, {from: daoOwner, gasPrice: toBN("0")});

    // 处理新提案
    await advanceTime(10000);

    await onboarding.processProposal(dao.address, proposalId, {from: advisorAccount, gasPrice: toBN("0")});

    // 检查发给新 Avisor 的 Loot （无投票权单位）的数量
    const advisorAccountLoot = await bank.balanceOf(advisorAccount, LOOT);
    expect(advisorAccountLoot.toString()).equal("100000000");

    const guildBalance = await bank.balanceOf(GUILD, oltContract.address);
    expect(guildBalance.toString()).equal("10");
  });
});
