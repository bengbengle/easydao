pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../guards/AdapterGuard.sol";
import "../guards/MemberGuard.sol";
import "../extensions/IExtension.sol";
import "../helpers/DaoHelper.sol";

contract DaoRegistry is MemberGuard, AdapterGuard {
    bool public initialized = false; // internally tracks deployment under eip-1167 proxy pattern

    // CREATION，刚创建 ，未设置，不能使用
    // READY 这个 DAO 已经设置好
    enum DaoState {
        CREATION,
        READY
    }

    /*
     * EVENTS
     */
    /// @dev - Events for Proposals
    event SubmittedProposal(bytes32 proposalId, uint256 flags);
    event SponsoredProposal(
        bytes32 proposalId,
        uint256 flags,
        address votingAdapter
    );
    event ProcessedProposal(bytes32 proposalId, uint256 flags);

    event AdapterAdded(
        bytes32 adapterId,
        address adapterAddress,
        uint256 flags
    );
    event AdapterRemoved(bytes32 adapterId);

    event ExtensionAdded(bytes32 extensionId, address extensionAddress);
    event ExtensionRemoved(bytes32 extensionId);

    /// @dev - Events for Members
    event UpdateDelegateKey(address memberAddress, address newDelegateKey);
    event ConfigurationUpdated(bytes32 key, uint256 value);
    event AddressConfigurationUpdated(bytes32 key, address value);

    enum MemberFlag {
        EXISTS
    }

    enum ProposalFlag {
        EXISTS,
        SPONSORED,
        PROCESSED
    }

    // 替换适配器
    // 提交提案
    // 更新委托者地址
    // 设置配置
    // 添加 EXTENSION
    // 移除 EXTENSION
    // 添加 Dao 成员
    enum AclFlag {
        REPLACE_ADAPTER,
        SUBMIT_PROPOSAL,
        UPDATE_DELEGATE_KEY,
        SET_CONFIGURATION,
        ADD_EXTENSION,
        REMOVE_EXTENSION,
        NEW_MEMBER
    }

    /*
     * STRUCTURES
     */
    struct Proposal {
        // 跟踪 DAO 中所有提案的结构， 调用函数以更改 DAO 状态的适配器地址
        address adapterAddress;
        // 跟踪提案状态的标志：存在、赞助、处理、取消等
        uint256 flags;
    }

    // 跟踪 DAO 中所有成员的结构， 用于跟踪成员状态的标志：存在等
    struct Member {
        uint256 flags;
    }

    // 用于标记给定区块的投票数的检查点
    struct Checkpoint {
        uint96 fromBlock;
        uint160 amount;
    }

    // 用于标记给定块中成员的委托密钥的检查点
    struct DelegateCheckpoint {
        uint96 fromBlock;
        address delegateKey;
    }

    struct AdapterEntry {
        bytes32 id;
        uint256 acl;
    }

    struct ExtensionEntry {
        bytes32 id;
        mapping(address => uint256) acl;
        bool deleted;
    }

    /*
     * PUBLIC VARIABLES
     */
    //  用于跟踪 DAO 的所有成员的地图
    mapping(address => Member) public members;
    address[] private _members;

    // delegate key => member address
    mapping(address => address) public memberAddressesByDelegatedKey;

    // memberAddress => checkpointNum => DelegateCheckpoint
    mapping(address => mapping(uint32 => DelegateCheckpoint)) checkpoints;

    // memberAddress => numDelegateCheckpoints
    mapping(address => uint32) numCheckpoints;

    DaoState public state;

    /// @notice 跟踪所有提交给 DAO 的提案 ，dao --> 提案
    mapping(bytes32 => Proposal) public proposals;

    /// @notice 跟踪每个proposalId 的投票适配器地址的映射，proposalId --> VotingAdapter
    mapping(bytes32 => address) public votingAdapter;

    /// @notice 跟踪在 DAO 中注册的所有适配器的映射，dao --> adapters
    mapping(bytes32 => address) public adapters;

    /// @notice 根据地址获取适配器 id 的逆映射 adapter_address --> [] {adapter_id, acl }
    mapping(address => AdapterEntry) public inverseAdapters;

    /// @notice 跟踪在 DAO 中注册的所有扩展的映射
    mapping(bytes32 => address) public extensions;

    /// @notice The inverse map to get the extension id based on its address, addr --> ext
    /// @notice 根据地址获取扩展ID的逆映射 ext_address --> []{ext_id, is_del, [acl]
    mapping(address => ExtensionEntry) public inverseExtensions;

    /// @notice 跟踪 DAO 和适配器的配置参数的映射
    mapping(bytes32 => uint256) public mainConfiguration;
    mapping(bytes32 => address) public addressConfiguration;

    uint256 public lockedAt;

    /// @notice 可克隆合约必须有一个空的构造函数
    constructor() {}

    /**
     * @notice 初始化 DAO
     * @dev 涉及初始化可用令牌、检查点和创建者的成员资格
     * @dev 只能调用一次
     * @param creator DAO 的创建者，他将成为初始成员
     * @param payer 为创建 DAO 的交易支付的账户，他将成为初始成员
     */
    function initialize(address creator, address payer) external {
        require(!initialized, "dao already initialized");
        initialized = true;
        potentialNewMember(msg.sender);
        potentialNewMember(payer);
        potentialNewMember(creator);
    }

    /**
     * @dev Sets the state of the dao to READY
     * @dev 将 dao 的状态设置为 READY
     */
    function finalizeDao() external {
        require(
            isActiveMember(this, msg.sender) || isAdapter(msg.sender),
            "not allowed to finalize"
        );
        state = DaoState.READY;
    }

    /**
     * @notice lock 策略 锁定 调用者是 adapter 或 ext
     */
    function lockSession() external {
        if (isAdapter(msg.sender) || isExtension(msg.sender)) {
            lockedAt = block.number;
        }
    }

    /**
     * @notice lock 策略 释放 只有调用者是适配器或扩展
     */
    function unlockSession() external {
        if (isAdapter(msg.sender) || isExtension(msg.sender)) {
            lockedAt = 0;
        }
    }

    /**
     * @notice 设置配置值， 更改配置映射中键的值
     * @param key 将为其设置值的配置键
     * @param value 要设置键的值
     */
    function setConfiguration(bytes32 key, uint256 value)
        external
        hasAccess(this, AclFlag.SET_CONFIGURATION)
    {
        mainConfiguration[key] = value;

        emit ConfigurationUpdated(key, value);
    }

    /**
     * @notice 如果成员地址未注册或无效，则在 DAO 中注册成员地址  
     * @notice 潜在会员是 不持有股份 的会员，其 注册 仍需投票 
     */
    function potentialNewMember(address memberAddress)
        public
        hasAccess(this, AclFlag.NEW_MEMBER)
    {
        require(memberAddress != address(0x0), "invalid member address");

        Member storage member = members[memberAddress];

        bool is_exists = DaoHelper.getFlag(
            member.flags,
            uint8(MemberFlag.EXISTS)
        );

        if (!is_exists) {
            require(
                memberAddressesByDelegatedKey[memberAddress] == address(0x0),
                "member address already taken as delegated key"
            );

            member.flags = DaoHelper.setFlag(
                member.flags,
                uint8(MemberFlag.EXISTS),
                true
            );

            memberAddressesByDelegatedKey[memberAddress] = memberAddress;
            _members.push(memberAddress);
        }

        address bankAddress = extensions[DaoHelper.BANK];
        if (bankAddress != address(0x0)) {
            BankExtension bank = BankExtension(bankAddress);

            if (bank.balanceOf(memberAddress, DaoHelper.MEMBER_COUNT) == 0) {
                bank.addToBalance(
                    this,
                    memberAddress,
                    DaoHelper.MEMBER_COUNT,
                    1
                );
            }
        }
    }

    /**
     * @notice 设置配置值， 改变配置映射中某个键的值
     * @param key 要设置值的配置键
     * @param value 设置key的值
     */
    function setAddressConfiguration(bytes32 key, address value)
        external
        hasAccess(this, AclFlag.SET_CONFIGURATION)
    {
        addressConfiguration[key] = value;

        emit AddressConfigurationUpdated(key, value);
    }

    /**
     * @return 根据 key 获取配置中的 value
     * @param key 在配置映射中查找的key
     */
    function getConfiguration(bytes32 key) external view returns (uint256) {
        return mainConfiguration[key];
    }

    /**
     * @return 特定键的配置值
     * @param key 在配置映射中查找的key
     */
    function getAddressConfiguration(bytes32 key)
        external
        view
        returns (address)
    {
        return addressConfiguration[key];
    }

    /**
     * @notice 为适配器添加 ACL 标志，以使可以访问扩展的功能, setAdapterAccessToExtension  Access Control Layer
     */
    function setAclToExtensionForAdapter(
        address extensionAddress,
        address adapterAddress,
        uint256 acl
    ) external hasAccess(this, AclFlag.ADD_EXTENSION) {
        require(isAdapter(adapterAddress), "not an adapter");
        require(isExtension(extensionAddress), "not an extension");

        inverseExtensions[extensionAddress].acl[adapterAddress] = acl;
    }

    /**
     * @notice 更改注册表中的适配器, 它处理适配器的 添加和删除 作为特殊情况
     * @notice 如果 adapterId 映射到现有适配器地址，则删除当前适配器
     * @dev 如果 adapterAddress 参数不为零，它会添加一个适配器
     * @param adapterId 适配器的唯一标识符
     * @param adapterAddress 新适配器的地址， 如果是删除操作， 则为零
     * @param acl 表示新适配器的访问控制层或权限的标志
     * @param keys 表示适配器配置名称的键
     * @param values 表示适配器配置值的值
     */
    function replaceAdapter(
        bytes32 adapterId,
        address adapterAddress,
        uint128 acl,
        bytes32[] calldata keys,
        uint256[] calldata values
    ) external hasAccess(this, AclFlag.REPLACE_ADAPTER) {
        require(adapterId != bytes32(0), "adapterId must not be empty");

        address currentAdapterAddr = adapters[adapterId];
        if (currentAdapterAddr != address(0x0)) {
            delete inverseAdapters[currentAdapterAddr];
            delete adapters[adapterId];
            emit AdapterRemoved(adapterId);
        }

        for (uint256 i = 0; i < keys.length; i++) {
            bytes32 key = keys[i];
            uint256 value = values[i];
            mainConfiguration[key] = value;
            emit ConfigurationUpdated(key, value);
        }

        if (adapterAddress != address(0x0)) {
            require(
                inverseAdapters[adapterAddress].id == bytes32(0),
                "adapterAddress already in use"
            );

            adapters[adapterId] = adapterAddress;
            inverseAdapters[adapterAddress].id = adapterId;
            inverseAdapters[adapterAddress].acl = acl;
            emit AdapterAdded(adapterId, adapterAddress, acl);
        }
    }

    /**
     * @notice 向注册表添加新扩展
     * @param extensionId 新扩展的唯一标识符
     * @param extension 扩展的地址
     * @param creator DAO 的创建者，他将成为初始成员
     */
    function addExtension(
        bytes32 extensionId,
        IExtension extension,
        address creator
    ) external hasAccess(this, AclFlag.ADD_EXTENSION) {
        require(extensionId != bytes32(0), "extension id must not be empty");
        require(
            extensions[extensionId] == address(0x0),
            "extension Id already in use"
        );
        require(
            !inverseExtensions[address(extension)].deleted,
            "extension can not be re-added"
        );

        extensions[extensionId] = address(extension);

        inverseExtensions[address(extension)].id = extensionId;

        extension.initialize(this, creator);

        emit ExtensionAdded(extensionId, address(extension));
    }

    /**
     * @notice Removes an adapter from the registry
     * @param extensionId The unique identifier of the extension
     * @notice 从注册表中移除一个适配器
     * @param extensionId 扩展的唯一标识符
     */
    function removeExtension(bytes32 extensionId)
        external
        hasAccess(this, AclFlag.REMOVE_EXTENSION)
    {
        require(extensionId != bytes32(0), "extensionId must not be empty");
        address extensionAddress = extensions[extensionId];
        require(extensionAddress != address(0x0), "extensionId not registered");

        ExtensionEntry storage extEntry = inverseExtensions[extensionAddress];
        extEntry.deleted = true;

        delete inverseExtensions[extensionAddress];
        delete extensions[extensionId];
        emit ExtensionRemoved(extensionId);
    }

    /**
     * @notice 查找给定地址是否有扩展名
     * @return 地址是否为分机
     * @param extensionAddr 要查找的地址
     */
    function isExtension(address extensionAddr) public view returns (bool) {
        return inverseExtensions[extensionAddr].id != bytes32(0);
    }

    /**
     * @notice 查找是否存在给定地址的适配器
     * @return 地址是否为适配器
     * @param adapterAddress 要查找的地址
     */
    function isAdapter(address adapterAddress) public view returns (bool) {
        return inverseAdapters[adapterAddress].id != bytes32(0);
    }

    /**
     * @notice 检查适配器是否具有给定的 ACL 标志
     * @return 给定的适配器是否设置了给定的标志
     * @param adapterAddress 要查找的地址
     * @param flag 用于检查给定地址的 ACL 标志
     */
    function hasAdapterAccess(address adapterAddress, AclFlag flag)
        external
        view
        returns (bool)
    {
        return
            DaoHelper.getFlag(inverseAdapters[adapterAddress].acl, uint8(flag));
    }

    /**
     * @notice 检查 适配器 是否具有给定的 ACL 标志
     * @return 给定的适配器是否设置了给定的标志
     * @param adapterAddress 要查找的地址
     * @param flag 用于检查给定地址的 ACL 标志
     */
    function hasAdapterAccessToExtension(
        address adapterAddress,
        address extensionAddress,
        uint8 flag
    ) external view returns (bool) {
        uint256 flags = inverseExtensions[extensionAddress].acl[adapterAddress];

        return
            isAdapter(adapterAddress) && DaoHelper.getFlag(flags, uint8(flag));
    }

    /**
     * @return 给定适配器 ID 的地址
     * @param adapterId 要查找的 ID
     */
    function getAdapterAddress(bytes32 adapterId)
        external
        view
        returns (address)
    {
        require(adapters[adapterId] != address(0), "adapter not found");
        return adapters[adapterId];
    }

    /**
     * @return 给定扩展 ID 的地址
     * @param extensionId 要查找的 ID
     */
    function getExtensionAddress(bytes32 extensionId)
        external
        view
        returns (address)
    {
        require(extensions[extensionId] != address(0), "extension not found");
        return extensions[extensionId];
    }

    /**
     * @notice 向 DAO 注册表提交提案
     */
    function submitProposal(bytes32 proposalId)
        external
        hasAccess(this, AclFlag.SUBMIT_PROPOSAL)
    {
        require(proposalId != bytes32(0), "invalid proposalId");

        bool is_exists = getProposalFlag(proposalId, ProposalFlag.EXISTS);

        require(!is_exists, "proposalId must be unique");

        // “1” 表示只设置了第一个标志，即 EXISTS
        proposals[proposalId] = Proposal(msg.sender, 1);

        emit SubmittedProposal(proposalId, 1);
    }

    /**
     * @notice 提交给 DAO 注册中心的提案， 将 SPONSORED 添加到提案标志
     * @param proposalId 提案的 ID
     * @param sponsoringMember 提案的成员
     * @param votingAdapterAddr voting adapter 地址
     */
    function sponsorProposal(
        bytes32 proposalId,
        address sponsoringMember,
        address votingAdapterAddr
    ) external onlyMember2(this, sponsoringMember) {
        // 检查 flag 是否 设置过
        Proposal storage proposal = _setProposalFlag(
            proposalId,
            ProposalFlag.SPONSORED
        );

        uint256 flags = proposal.flags;

        bool isProcessed = DaoHelper.getFlag(
            flags,
            uint8(ProposalFlag.PROCESSED)
        );

        // 只有提交提案的适配器才能处理它
        require(
            proposal.adapterAddress == msg.sender,
            "only the adapter that submitted the proposal can process it"
        );

        // 提案 必须未被处理
        require(!isProcessed, "proposal already processed");

        votingAdapter[proposalId] = votingAdapterAddr;

        emit SponsoredProposal(proposalId, flags, votingAdapterAddr);
    }

    /**
     * @notice Mark a proposal as processed in the DAO registry
     * @param proposalId The ID of the proposal that is being processed
     * @notice 在 DAO 注册表中将提案标记为已处理
     * @param proposalId 正在处理的提案的 ID
     */
    function processProposal(bytes32 proposalId) external {
        Proposal storage proposal = _setProposalFlag(
            proposalId,
            ProposalFlag.PROCESSED
        );

        require(proposal.adapterAddress == msg.sender, "err::adapter mismatch");
        uint256 flags = proposal.flags;

        emit ProcessedProposal(proposalId, flags);
    }

    /**
     * @notice 设置提案的标志
     * @dev 如果提案已经处理，则恢复
     * @param proposalId 要更改的提案ID
     * @param flag 将在提案上设置的标志
     */
    function _setProposalFlag(bytes32 proposalId, ProposalFlag flag)
        internal
        returns (Proposal storage)
    {
        Proposal storage proposal = proposals[proposalId];

        uint256 flags = proposal.flags;

        require(
            DaoHelper.getFlag(flags, uint8(ProposalFlag.EXISTS)),
            "proposal does not exist for this dao"
        );

        require(
            proposal.adapterAddress == msg.sender,
            "invalid adapter try to set flag"
        );

        require(!DaoHelper.getFlag(flags, uint8(flag)), "flag already set");

        flags = DaoHelper.setFlag(flags, uint8(flag), true);

        proposals[proposalId].flags = flags;

        return proposals[proposalId];
    }

    /*
     * MEMBERS
     */

    /**
     * @return 给定地址是否是 DAO 的成员
     * @dev 它将通过委托密钥解决，而不是成员地址
     * @param addr 要查找的地址
     */
    function isMember(address addr) external view returns (bool) {
        address memberAddress = memberAddressesByDelegatedKey[addr];
        return getMemberFlag(memberAddress, MemberFlag.EXISTS);
    }

    /**
     * @return 是否为 提案 设置了 标志
     * @param proposalId 要检查标志的提案
     * @param flag 要签入提案的标志
     */
    function getProposalFlag(bytes32 proposalId, ProposalFlag flag)
        public
        view
        returns (bool)
    {
        return DaoHelper.getFlag(proposals[proposalId].flags, uint8(flag));
    }

    /**
     * @return 是否 为成员 设置了 标志
     * @param memberAddress 要检查标志的成员
     * @param flag 签入成员的标志
     */
    function getMemberFlag(address memberAddress, MemberFlag flag)
        public
        view
        returns (bool)
    {
        return DaoHelper.getFlag(members[memberAddress].flags, uint8(flag));
    }

    /**
     * @return 成员长度
     */
    function getNbMembers() external view returns (uint256) {
        return _members.length;
    }

    // 成员地址
    function getMemberAddress(uint256 index) external view returns (address) {
        return _members[index];
    }

    /**
     * @notice 更新成员的委托密钥
     * @param memberAddr 进行委托的成员
     * @param newDelegateKey 被委托的成员
     */
    function updateDelegateKey(address memberAddr, address newDelegateKey)
        external
        hasAccess(this, AclFlag.UPDATE_DELEGATE_KEY)
    {
        require(newDelegateKey != address(0x0), "newDelegateKey cannot be 0");

        // 检查成员是否将 委托地址 设置为 其成员地址
        if (newDelegateKey != memberAddr) {
            require(
                memberAddressesByDelegatedKey[newDelegateKey] == address(0x0),
                "cannot overwrite existing delegated keys"
            );
        } else {
            require(
                memberAddressesByDelegatedKey[memberAddr] == address(0x0),
                "address already taken as delegated key"
            );
        }

        Member storage member = members[memberAddr];

        bool isExist = DaoHelper.getFlag(
            member.flags,
            uint8(MemberFlag.EXISTS)
        );
        require(isExist, "member does not exist");

        // 重置当前的委托
        memberAddressesByDelegatedKey[
            getCurrentDelegateKey(memberAddr)
        ] = address(0x0);

        memberAddressesByDelegatedKey[newDelegateKey] = memberAddr;

        _createNewDelegateCheckpoint(memberAddr, newDelegateKey);
        emit UpdateDelegateKey(memberAddr, newDelegateKey);
    }

    /**
     * Public read-only functions
     */

    /**
     * @param checkAddr 检查委托的地址
     * @return 委托的地址， 如果不是委托， 则返回检查的地址
     */
    function getAddressIfDelegated(address checkAddr)
        external
        view
        returns (address)
    {
        address delegatedKey = memberAddressesByDelegatedKey[checkAddr];
        return delegatedKey == address(0x0) ? checkAddr : delegatedKey;
    }

    /**
     * @param 将返回其委托的成员
     * @return 成员当前时间的委托 地址
     */
    function getCurrentDelegateKey(address memberAddr)
        public
        view
        returns (address)
    {
        uint32 nCheckpoints = numCheckpoints[memberAddr];
        return
            nCheckpoints > 0
                ? checkpoints[memberAddr][nCheckpoints - 1].delegateKey
                : memberAddr;
    }

    /**
     * @param memberAddr 要查找的成员地址
     * @return 倒数第二个 检查点 的 memberAddr 的委托密钥地址
     */
    function getPreviousDelegateKey(address memberAddr)
        external
        view
        returns (address)
    {
        uint32 nCheckpoints = numCheckpoints[memberAddr];
        return
            nCheckpoints > 1
                ? checkpoints[memberAddr][nCheckpoints - 2].delegateKey
                : memberAddr;
    }

    /**
     * @notice 确定一个账户在区块号之前的投票数 
     * @dev 区块编号必须是最终区块，否则此功能将恢复以防止错误信息  
     * @param memberAddr 要检查的账户地址 
     * @param blockNumber 获得投票余额的区块号 
     * @return 给定区块中的 委托地址
     */
    function getPriorDelegateKey(address memberAddr, uint256 blockNumber)
        external
        view
        returns (address)
    {
        require(blockNumber < block.number, "Uni::getPriorDelegateKey: NYD");

        uint32 nCheckpoints = numCheckpoints[memberAddr];
        if (nCheckpoints == 0) {
            return memberAddr;
        }

        // 首先检查最近的余额
        if (
            checkpoints[memberAddr][nCheckpoints - 1].fromBlock <= blockNumber
        ) {
            return checkpoints[memberAddr][nCheckpoints - 1].delegateKey;
        }

        // 接下来检查隐式零余额
        if (checkpoints[memberAddr][0].fromBlock > blockNumber) {
            return memberAddr;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            DelegateCheckpoint memory cp = checkpoints[memberAddr][center];
            if (cp.fromBlock == blockNumber) {
                return cp.delegateKey;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[memberAddr][lower].delegateKey;
    }

    /**
     * @notice 创建某个成员的新委托检查点
     * @param member 委托检查点将被添加到的成员
     * @param newDelegateKey 将被写入新检查点的委托密钥
     */
    function _createNewDelegateCheckpoint(
        address member,
        address newDelegateKey
    ) internal {
        uint32 nCheckpoints = numCheckpoints[member];
        // 我们应该允许 deletegaKey 升级的唯一条件 
        // 当 block.number 与 fromBlock 值完全匹配时  
        // 任何与此不同的东西都应该生成一个新的检查点 
        if (nCheckpoints > 0 && checkpoints[member][nCheckpoints - 1].fromBlock == block.number) {
            checkpoints[member][nCheckpoints - 1].delegateKey = newDelegateKey;
        } else {
            checkpoints[member][nCheckpoints] = DelegateCheckpoint(
                uint96(block.number),
                newDelegateKey
            );
            numCheckpoints[member] = nCheckpoints + 1;
        }
    }
}
