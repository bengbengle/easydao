// Whole-script strict mode syntax
"use strict";

const { toWei, toBN, fromAscii, GUILD } = require("../../utils/contract-util");

const {
  takeChainSnapshot,
  revertChainSnapshot,
  deployDefaultNFTDao,
  accounts,
  expectRevert,
  expect,
  web3,
} = require("../../utils/oz-util");

const { encodeDaoInfo } = require("../../utils/test-util");

describe("Extension - ERC721", () => {
  const daoOwner = accounts[0];

  before("deploy dao", async () => {
    const { dao, adapters, extensions, testContracts } = await deployDefaultNFTDao({ owner: daoOwner });
    this.dao = dao;
    this.adapters = adapters;
    this.extensions = extensions;
    this.testContracts = testContracts;
  });

  beforeEach(async () => {
    this.snapshotId = await takeChainSnapshot();
  });

  afterEach(async () => {
    await revertChainSnapshot(this.snapshotId);
  });

  // 应该可以创建一个预先配置了 nft 扩展的 dao
  it("should be possible to create a dao with a nft extension pre-configured", async () => {
    const nftExtension = this.extensions.erc721Ext;
    expect(nftExtension).to.not.be.null;
  });

  // 应该可以检查集合中有多少 NFT
  it("should be possible check how many NFTs are in the collection", async () => {
    const nftExtension = this.extensions.erc721Ext;
    const pixelNFT = this.testContracts.pixelNFT;
    const total = await nftExtension.nbNFTs(pixelNFT.address);
    expect(total.toString()).equal("0");
  });

  // 如果集合为空，则不可能在集合中获得 NFT
  it("should not be possible get an NFT in the collection if it is empty", async () => {
    const nftExtension = this.extensions.erc721Ext;
    const pixelNFT = this.testContracts.pixelNFT;
    await expectRevert(
      nftExtension.getNFT(pixelNFT.address, 0), 
      "revert"
    );
  });

  // 没有 RETURN 许可，应该不可能返回 NFT
  it("should not be possible to return a NFT without the RETURN permission", async () => {
    const nftExtension = this.extensions.erc721Ext;
    const pixelNFT = this.testContracts.pixelNFT;
    await expectRevert(
      nftExtension.withdrawNFT(
        this.dao.address,
        accounts[1],
        pixelNFT.address,
        1
      ),
      "erc721::accessDenied"
    );
  });

  // 应该可以 检查集合中有多少 NFT
  it("should be possible check how many NFTs are in the collection", async () => {
    const nftExtension = this.extensions.erc721Ext;
    const total = await nftExtension.nbNFTAddresses();
    expect(total.toString()).equal("0");
  });

  // 如果扩展已经初始化， 则应该无法初始化它
  it("should not be possible to initialize the extension if it was already initialized", async () => {
    const nftExtension = this.extensions.erc721Ext;
    await expectRevert(
      nftExtension.initialize(this.dao.address, accounts[0]),
      "erc721::already initialized"
    );
  });

  // 应该可以收集直接发送到扩展的 NFT
  it("should be possible to collect a NFT that is send directly to the extension", async () => {
    const nftOwner = accounts[2];
    const dao = this.dao;
    const pixelNFT = this.testContracts.pixelNFT;
    const nftExtension = this.extensions.erc721Ext;

    await pixelNFT.mintPixel(nftOwner, 1, 1, { from: daoOwner });
    let pastEvents = await pixelNFT.getPastEvents();
    let { tokenId } = pastEvents[1].returnValues;

    const firstOwner = await pixelNFT.ownerOf(tokenId);
    expect(firstOwner).equal(nftOwner);

    await pixelNFT.methods["safeTransferFrom(address,address,uint256,bytes)"](
      nftOwner,
      nftExtension.address,
      tokenId,
      encodeDaoInfo(dao.address),
      {
        from: nftOwner,
      }
    );

    // Make sure it was collected in the NFT Extension
    const nftAddr = await nftExtension.getNFTAddress(0);
    expect(nftAddr).equal(pixelNFT.address);
    const nftId = await nftExtension.getNFT(nftAddr, 0);
    expect(nftId.toString()).equal(tokenId.toString());

    // The NFT belongs to the GUILD after it is collected via ERC721 Extension
    const newOwner = await nftExtension.getNFTOwner(nftAddr, tokenId);
    expect(newOwner.toLowerCase()).equal(GUILD);

    // The actual holder of the NFT is the ERC721 Extension
    const holder = await pixelNFT.ownerOf(tokenId);
    expect(holder).equal(nftExtension.address);
  });

  it("should not be possible to send ETH to the extension via receive function", async () => {
    const extension = this.extensions.erc721Ext;
    await expectRevert(
      web3.eth.sendTransaction({
        to: extension.address,
        from: daoOwner,
        gasPrice: toBN("0"),
        value: toWei("1"),
      }),
      "revert"
    );
  });

  it("should not be possible to send ETH to the extension via fallback function", async () => {
    const extension = this.extensions.erc721Ext;
    await expectRevert(
      web3.eth.sendTransaction({
        to: extension.address,
        from: daoOwner,
        gasPrice: toBN("0"),
        value: toWei("1"),
        data: fromAscii("should go to fallback func"),
      }),
      "revert"
    );
  });
});
