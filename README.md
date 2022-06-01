<div align="center">
    <!-- <img src="https://demo.EasyDAO.com/favicon.ico" height="70" alt="EasyDao DAO Framework Logo"> -->
    <h1>EasyDao</h1>
    <strong> 一站式 DAO 解决方案 </strong>
</div>

## Contents

- [Overview](#overview)
- [Proposal](#proposed-evolution-of-molochdao-framework)
- [Architecture](#tribute-dao-architecture)
- [Quickstart](#quickstart)
- [Release](#release)
- [Contribute](#contribute)
- [Community](#community)
- [Thank You](#thank-you)
- [License](#license)

## Overview

EasyDAO 是一个新的模块化、低成本的 DAO 框架。 该框架旨在通过修复以下问题来改进 DAO：

- **Lack of modularity**:  在扩展、管理和升级 DAO 方面都带来了挑战；
- **Rigid voting and governance mechanisms**: 限制了尝试其他治理形式的能力；
- **High costs**: 特别是对于链上投票；
- **Single token DAO structures**: 这使得划分 经济 和 治理权 以及 创建团队 或 子群体 变得困难；
- **Lack of NFT Support**:  DAO 很难部署到 NFT 项目中

EasyDAO 框架旨在解决这些问题，作为我们使 DAO 成为主要组织形式的努力的一部分。正如越来越多的 DAO 参与者所知道的那样，管理任何组织都没有“一刀切”的做法。 DAO 需要低成本且易于开发的组件，这些组件可以像乐高积木一样组装，以满足组织及其成员的需求

## MolochDAO 框架的演进

EasyDAO 框架是我们团队对 MolochDAO 生态系统的致敬。众所周知，MolochDAO 为 DAO 带来了新的活力。 通过优雅的智能合约设计， 这个智能合约框架让 DAO 重新焕发生机，帮助我们超越“The DAO”的火热深度

去年，我们通过协助创建 Moloch v2 来改进最初的 MolochDAO 智能合约， 该版本支持多种代币， “公会踢” 以删除不需要的成员， “战利品” 以发行仍有权获得财务分配的无投票权股份。 这些升级的合约是在考虑 “风险” 和类似的投资交易的情况下构建的， 允许更有效的交换和对代币化资产和成员的控制

EasyDAO 框架希望为希望部署 DAO 的团队提供多项增强和改进，包括：

- **Simpler code** - 每个模块只负责一个功能，从而减少耦合并使系统更易于理解.
- **Adaptability** - DAO 的每个部分都可以适应特定 DAO 的需求，而无需每次都审核整个代码库
- **Upgradability** - 模块可以根据需要轻松升级。 例如，随着投票过程的发展，负责管理投票过程的模块可以升级，而无需更改任何其他模块或核心合约。 模块也可以被多个 DAO 使用，而无需重新部署

受 [六边形架构设计模式](<https://en.wikipedia.org/wiki/Hexagonal_architecture_(software)>) 的启发，我们相信我们可以拥有额外的安全层，并将主合约分解为更小的合约
有了这个，我们创建了松散耦合的模块/合约，更容易审计，并且可以很容易地连接到 DAO

## EasyDAO 架构

![laoland_hexagon_architecture](https://user-images.githubusercontent.com/708579/107689684-e7300200-6c87-11eb-89c0-7bfe7eddaaaf.png)

主要设计目标是根据层边界限制对智能合约的访问。外部世界（即 RPC 客户端）只能通过适配器访问核心合约，而不能直接访问。每个适配器都包含所有必要的逻辑和数据，以在 DAORegistry 合约中更新/更改 DAO 的状态。 Core Contract 跟踪 DAO 的所有状态变化，而 Adapter 仅跟踪其自身上下文中的状态变化。扩展增强了 DAO 功能并简化了核心合约代码。信息总是从外部世界流向核心合约，而不是相反。如果核心合约需要外部信息，它必须由适配器和/或扩展提供，而不是直接调用外部世界

EasyDao 架构中有五个主要组件，下面将进一步概述

### Core Contracts

核心合约充当 EasyDAO 框架的支柱，并充当 DAO 注册表，创建“公司分工”的数字版本 这些合约构成了 DAO 本身， 并使部署 DAO 变得更便宜、更容易
这些合约直接改变 DAO 状态，而不需要通过适配器或扩展（下面进一步描述）核心合约从不直接从外部世界提取信息
因此，我们使用适配器和扩展，自然信息流总是从外部世界流向核心合约 

EasyDao 框架包含三个核心合约，包括：

- [DaoRegistry](https://EasyDAO.com/docs/contracts/core/dao-registry): 跟踪 DAO 的状态变化， 只有具有正确 [Access Flags](#access-control-layer) 的适配器才能更改 DAO 状态
- CloneFactory: 根据其地址创建 DAO 的克隆
- [DaoFactory](https://EasyDAO.com/docs/contracts/core/dao-factory): 创建、初始化和添加适配器配置到新的 DAO， 并使用 CloneFactory 降低 DAO 创建事务成本

### Adapters and Extensions

一旦使用上述核心合约创建了 DAO，就可以使用适配器和扩展对其进行扩展和修改 
适配器和扩展通过向 DAO 添加为特定目的而创建的经过严格定义、测试和可扩展的智能合约，可以轻松组装像乐高积木一样的 DAO 
适配器和扩展使 DAO 更加模块化、可升级，并使我们能够共同构建强大的 DAO 工具 
它们可以通过 DAO 投票添加到 EasyDAO 

#### Adapters

目前在 EasyDAO 框架中实现了 12 个适配器，这些适配器使 EasyDAO 框架功能与 Moloch v2 兼容：

- [Configuration](https://EasyDAO.com/docs/contracts/adapters/configuration/configuration-adapter): 管理共享适配器所需的每个 DAO 设置的存储和检索
- [Distribute](https://EasyDAO.com/docs/contracts/adapters/distribution/distribute-adapter): 允许成员将资金分配给 DAO 的一个或所有成员
- [Financing](https://EasyDAO.com/docs/contracts/adapters/funding/financing-adapter): 允许个人和/或组织申请资金来资助他们的项目，DAO 的成员有权投票决定应该资助哪些项目
- [GuildKick](https://EasyDAO.com/docs/contracts/adapters/exiting/guild-kick-adapter): 让成员可以自由选择哪些个人或组织真正应该成为 DAO 的一部分
- [Managing](https://EasyDAO.com/docs/contracts/adapters/configuration/managing-adapter): 通过投票过程添加/更新 DAO 适配器来增强 DAO 功能
- [OffchainVoting](https://EasyDAO.com/docs/contracts/adapters/voting/offchain-voting-adapter): 将链下投票治理流程添加到 DAO 以支持无气体投票
- [Onboarding](https://EasyDAO.com/docs/contracts/adapters/onboarding/onboarding-adapter): 触发以固定价格铸造内部代币以换取特定代币的过程
- [Ragequit](https://EasyDAO.com/docs/contracts/adapters/exiting/rage-quit-adapter): 让成员可以自由选择出于任何给定原因退出 DAO 的最佳时间
- [Tribute](https://EasyDAO.com/docs/contracts/adapters/onboarding/tribute-adapter): 允许潜在的和现有的 DAO 成员向 DAO 贡献任意数量的 ERC-20 代币，以换取任意数量的 DAO 内部代币
- [TributeNFT](https://EasyDAO.com/docs/contracts/adapters/onboarding/tribute-nft-adapter): 允许潜在的 DAO 成员向 DAO 贡献注册的 ERC-721 资产，以换取任何数量的 DAO 单位
- [Voting](https://EasyDAO.com/docs/contracts/adapters/voting/basic-voting-adapter): 将简单的链上投票治理流程添加到 DAO
- [Withdraw](https://EasyDAO.com/docs/contracts/adapters/utils/bank-adapter#withdraw): 允许成员从 DAO 银行提取资金

潜在适配器的范围将随着时间的推移而扩大，可能包括：

- [Streaming_Payments] 流式支付 
- [Streams] 更灵活的方式管理 DAO 的金库
- [Alternative_Voting_Structures_To_Layer] 分层的替代投票结构 用于改善 DAO 治理，包括二次投票、一人一票 投票
- [Swap] 将一个令牌换成另一个
- [NFT-Onboarding] 基于 NFT 的入职
- [DAO-to-DAO] DAO 到 DAO 投票
- [LiquidityPool] 为 DAO 的原生资产创建流动资金池 
- [Staking] [Depositing] 将资产质押 或 存入现有 DeFi 项目 （ 如 Aave、 Compound 或 Lido ）

创建适配器很简单，应该可以节省开发人员的工程时间。 每个适配器都需要配置 [Access Flags](#access-control-layer) 以访问 [Core Contracts](#core-contracts) 和/或 [Extensions](#extensions)
否则， 适配器将无法从 DAO 拉取/推送信息

- 适配器不跟踪 DAO 的状态 适配器可能使用存储来控制自己的状态， 但理想情况下， 任何 DAO 状态更改都必须传播到 DAORegistry 核心合约， 最好是无状态的
- 适配器只是执行智能合约逻辑，通过调用 DAORegistry 来改变 DAO 的状态 他们还可以编写与外部世界、其他适配器甚至扩展交互的复杂调用，以提取/推送附加信息  
- 适配器必须遵循 [模板适配器](https://EasyDAO.com/docs/tutorial/adapter/adapter-template) 定义的规则
- 如果您想贡献并创建适配器， 请查看：[如何创建适配器](https://EasyDAO.com/docs/tutorial/adapters/creating-an-adapter)

### Extensions

扩展旨在将状态更改的复杂性与 DAORegistry 合约隔离开来， 并简化核心逻辑。 本质上，扩展类似于适配器，但主要区别在于它被多个适配器和 DAORegistry 使用——最终增强了 DAO 功能和状态管理，而不会弄乱 DAO 核心合约

- [Bank](https://EasyDAO.com/docs/contracts/extensions/bank-extension): 将银行功能添加到 DAO，并跟踪 DAO 帐户和内部代币余额

- [NFT](https://EasyDAO.com/docs/contracts/extensions/nft-extension): 为 DAO 添加了管理和策划一组标准 NFT 的能力

- [ERC20](https://EasyDAO.com/docs/contracts/extensions/erc20-extension): 为 DAO 添加了在内部成员和/或外部账户之间 管理和转移内部代币的能力

- [Executor](https://EasyDAO.com/docs/contracts/extensions/executor-extension): 使用 EVM 指令 `delegatecall` 为 DAO 添加执行对其他合约的委托调用的能力， 包括不属于 DAO 的合约

#### Access Control Layer

访问控制层 (ACL) 是使用访问标志来实现的，以指示适配器必须具有哪些权限才能访问和修改 DAO 状态。 [访问标志]（https://EasyDAO.com/docs/intro/design/access-control）有 3 个主要类别：

- MemberFlag: `EXISTS`.
- ProposalFlag: `EXISTS`, `SPONSORED`, `PROCESSED`.
- AclFlag: `REPLACE_ADAPTER`, `SUBMIT_PROPOSAL`, `UPDATE_DELEGATE_KEY`, `SET_CONFIGURATION`, `ADD_EXTENSION`, `REMOVE_EXTENSION`, `NEW_MEMBER`.

当调用 `daoFactory.addAdapters` 函数传递新的适配器时， 必须将每个适配器的访问标志提供给 DAOFactory。 这些标志将授予对 DAORegistry 合约的访问权限，并且必须执行相同的过程来授予每个适配器对每个扩展的访问权限（函数 `daoFactory.configureExtension`）

访问标志在 DAORegistry 中使用修饰符 `hasAccess` 定义。例如，带有修饰符 `hasAccess(this, AclFlag.REPLACE_ADAPTER)` 的函数意味着调用此函数的适配器需要启用访问标志 `REPLACE_ADAPTER`，否则调用将恢复。为了创建具有正确访问标志的适配器，首先需要映射适配器将在 DAORegistry 和扩展中调用的所有函数，并使用如上所述的 DAO 工厂提供这些访问标志

您可以在 [DAO Registry - Access Flags](https://EasyDAO.com/docs/contracts/core/dao-registry#access-flags) 中找到有关每个访问标志用途的更多信息
## Quickstart

### Install all dependencies

```sh
npm ci
```

### Creating a .env file at the root

```sh
cp .sample.env .env
```

### Compile contracts

```sh
npm run compile
```

### Deploy contracts

将合约部署到 rinkeby、goerli、harmonitest、polygontest、ganache、mainnet、harmonic 或 polygon 等网络

```sh
npm run deploy rinkeby
```

OR

```sh
npm run deploy goerli
```

OR

```sh
npm run deploy harmonytest
```

OR

```sh
npm run deploy polygontest
```

OR

```sh
npm run deploy mainnet
```

OR

```sh
npm run deploy harmony
```

OR

```sh
npm run deploy polygon
```

For more information about the deployment, see the in logs [logs/contracts](logs/contracts)

### Verify contracts

```sh
npm run verify rinkeby
```

OR

```sh
npm run verify mainnet
```

### DApp setup

In the same `.env` file created under the `easydao-contracts` folder, set the following environment variables:

```
######################## EasyDAO UI env vars ########################

# Configure the UI to use the Rinkeby network for local development
REACT_APP_DEFAULT_CHAIN_NAME_LOCAL=RINKEBY

# It can be the same value you used for the EasyDAO deployment.
REACT_APP_INFURA_PROJECT_ID_DEV=YOUR_INFURA_API_KEY

# The address of the Multicall smart contract deployed to the Rinkeby network.
# Copy that from the easydao-contracts/build/contracts-rinkeby-YYYY-MM-DD-HH:mm:ss.json
REACT_APP_MULTICALL_CONTRACT_ADDRESS=0x...

# The address of the DaoRegistry smart contract deployed to the Rinkeby network.
# Copy that from the easydao-contracts/build/contracts-rinkeby-YYYY-MM-DD-HH:mm:ss.json
REACT_APP_DAO_REGISTRY_CONTRACT_ADDRESS=0x...

# Enable Rinkeby network for EasyDAO UI
REACT_APP_ENVIRONMENT=development
```

Make sure you have set the correct addresses for `REACT_APP_MULTICALL_CONTRACT_ADDRESS` & `REACT_APP_DAO_REGISTRY_CONTRACT_ADDRESS`.

### DAO Launch

From the `easydao-contracts/docker` folder, run:

- > docker-compose up

### Linter

List the problems found in project files

```sh
npm run lint
```

Fix the lint issues

```sh
npm run lint:fix
```

### Slither

```sh
npm run slither
```

### Tests

```sh
npm test
```

### Environment variables

Contracts:

- `DAO_NAME`: DAO 的名称
- `DAO_OWNER_ADDR`: 目标网络中的 DAO 所有者 ETH 地址 (0x...)
- `ETH_NODE_URL`: 连接以太坊区块链的以太坊节点 URL，可以是 http/ws
- `WALLET_MNEMONIC`: 包含 12 个秘密关键字的钱包助记符字符串
- `ETHERSCAN_API_KEY`: 用于在部署后验证合约的 Ether Scan API 密钥
- `DEBUG`: 调试 Ether Scan 合约验证调用 (`true`|`false`).
- `COUPON_CREATOR_ADDR`: 入职优惠券创建者的公共地址
- `ERC20_TOKEN_NAME`: ERC20 代币扩展使用的 ERC20 代币名称
- `ERC20_TOKEN_SYMBOL`: ERC20 代币扩展使用的代币符号
- `ERC20_TOKEN_DECIMALS`: 在 MetaMask 中显示的 ERC20 代币小数
- `OFFCHAIN_ADMIN_ADDR`: 管理链下投票适配器的管理员帐户的地址
- `VOTING_PERIOD_SECONDS`: 允许成员对提案进行投票的最长时间（以秒为单位）
- `GRACE_PERIOD_SECONDS`: 投票期结束后，成员在处理提案之前需要等待的最短时间（以秒为单位）.
- `DAO_ARTIFACTS_OWNER_ADDR`: 部署的工件的所有者地址。如果您想使用 `DAO_OWNER_ADDR` 作为工件所有者，请将其留空
- `DAO_ARTIFACTS_CONTRACT_ADDR`: `DaoArtifacts` 合约地址，将在部署脚本中用于在部署期间获取适配器和工厂，以节省 gas 成本

Snapshot-hub:

- `PORT`: The Snapshot hub Server port
- `ENV`: To indicate in which environment it is being executed: local, dev, or prod
- `USE_IPFS`: To indicated the pinning service on IPFS should be enabled/disabled (if enabled cause delay in the responses)
- `RELAYER_PK`: The PK of the account that will be used to sign the messages.
- `NETWORK`: The network name that will be used by the relayer (use testnet for: rinkeby or ropsten), and mainnet for the main eth network
- `JAWSDB_URL`: The postgres url: postgres://user:pwd@host:5432/db-name
- `ALLOWED_DOMAINS`: The list of domains that should be allowed to send requests to the API
- `ALCHEMY_API_URL`: The relayer API (alternative to Infura)

Tribute-UI:

- `REACT_APP_DEFAULT_CHAIN_NAME_LOCAL`: The network which the dApp needs to connect to.
- `REACT_APP_INFURA_PROJECT_ID_DEV`: Your infura key.
- `REACT_APP_DAO_REGISTRY_CONTRACT_ADDRESS`: The address of the `DaoRegistry` smart contract deployed, copy that from `build/deployed/contracts-network-YYYY-MM-DD-HH:mm:ss.json`
- `REACT_APP_MULTICALL_CONTRACT_ADDRESS`: The address of the `Multicall` smart contract deployed, copy that from `build/deployed/contracts-network-YYYY-MM-DD-HH:mm:ss.json`.
- `REACT_APP_ENVIRONMENT`: The environment which the app will be executed. Set it to `development` env.

## Release

1. Checkout `master` and pull the latest
2. Locally run `npm run release`
3. Choose a new semver version number
4. **In the background the following will happen**:
   1. the `package.json` version will be bumped
   2. a new Git tag is created
   3. package version bump and tag pushed to `master`
   4. GitHub Release page will open, set the release name, edit the changelog if needed, and publish
   5. `publish.yaml` will execute (due to the new release tag) to publish the new package version to the NPM registry.
5. Done!

## Contribute

EasyDao exists thanks to its contributors. There are many ways you can participate and help build high quality software. Check out the [contribution guide](CONTRIBUTING.md)!

## Community

Join us on [Discord](https://discord.gg/xXMA2DYqNf).

## Thank You

**THANK YOU** to **all** coders, designers, auditors, and any individual who have contributed with ideas, resources, and energy to this and previous versions of this project. [Thank you all](https://EasyDAO.com/docs/thanks).

## License

EasyDao is released under the [MIT License](LICENSE).
