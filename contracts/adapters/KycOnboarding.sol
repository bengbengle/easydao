pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "../guards/AdapterGuard.sol";
import "../utils/Signatures.sol";
import "../helpers/WETH.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./modifiers/Reimbursable.sol";

contract KycOnboardingContract is
    AdapterGuard,
    MemberGuard,
    Signatures,
    Reimbursable
{
    using Address for address payable;
    using SafeERC20 for IERC20;

    event Onboarded(DaoRegistry dao, address member, uint256 units);
    struct Coupon {
        address kycedMember;
    }

    struct OnboardingDetails {
        uint88 chunkSize;
        uint88 numberOfChunks;
        uint88 unitsPerChunk;
        uint88 unitsRequested;
        uint88 maximumTotalUnits;
        uint160 amount;
    }

    string public constant COUPON_MESSAGE_TYPE = "Message(address kycedMember)";
    bytes32 public constant COUPON_MESSAGE_TYPEHASH = keccak256(abi.encodePacked(COUPON_MESSAGE_TYPE));

    bytes32 constant SignerAddressConfig = keccak256("kyc-onboarding.signerAddress");
    bytes32 constant ChunkSize = keccak256("kyc-onboarding.chunkSize");
    bytes32 constant UnitsPerChunk = keccak256("kyc-onboarding.unitsPerChunk");
    bytes32 constant MaximumChunks = keccak256("kyc-onboarding.maximumChunks");
    bytes32 constant MaximumUnits = keccak256("kyc-onboarding.maximumTotalUnits");
    bytes32 constant MaxMembers = keccak256("kyc-onboarding.maxMembers");
    bytes32 constant FundTargetAddress = keccak256("kyc-onboarding.fundTargetAddress");
    bytes32 constant TokensToMint = keccak256("kyc-onboarding.tokensToMint");

    WETH private _weth;
    IERC20 private _weth20;

    mapping(DaoRegistry => mapping(address => uint256)) public totalUnits;

    constructor(address payable weth) {
        _weth = WETH(weth);
        _weth20 = IERC20(weth);
    }

    /**
     * @notice 使用 优惠券 签名者地址 和 要铸造的令牌配置适配器
     * @param dao 要配置的 dao 
     * @param signerAddress 签名者的地址 
     
     * @param chunkSize 有多少个块 
     * @param unitsPerChunk 我们每个块有多少单位 
     
     * @param maximumChunks 允许的最大块数 
     * @param maxUnits 可以铸造多少内部代币 
     * @param maxMembers 允许加入的最大成员数 

     * @param fundTargetAddress 用于转账的多重签名地址，如果您不想使用多重签名，请将其设置为 address(0) 
     
     * @param tokenAddr 可以进行入职的代币 
     * @param internalTokensToMint 成员加入 DAO 时将被铸造的代币
     */
    function configureDao(
        DaoRegistry dao,
        address signerAddress,

        uint256 chunkSize,
        uint256 unitsPerChunk,

        uint256 maximumChunks,
        uint256 maxUnits,
        uint256 maxMembers,

        address fundTargetAddress,
        address tokenAddr,
        address internalTokensToMint
    ) external onlyAdapter(dao) {
        require(
            chunkSize > 0 && chunkSize < type(uint88).max,
            "chunkSize::invalid"
        );
        require(
            maxMembers > 0 && maxMembers < type(uint88).max,
            "maxMembers::invalid"
        );
        require(
            maximumChunks > 0 && maximumChunks < type(uint88).max,
            "maximumChunks::invalid"
        );
        require(
            maxUnits > 0 && maxUnits < type(uint88).max,
            "maxUnits::invalid"
        );
        require(
            unitsPerChunk > 0 && unitsPerChunk < type(uint88).max,
            "unitsPerChunk::invalid"
        );
        require(
            maximumChunks * unitsPerChunk < type(uint88).max,
            "potential overflow"
        );

        require(
            DaoHelper.isNotZeroAddress(signerAddress),
            "signer address is nil!"
        );

        require(
            DaoHelper.isNotZeroAddress(internalTokensToMint),
            "null internal token address"
        );

        dao.setAddressConfiguration(
            _configKey(tokenAddr, SignerAddressConfig),
            signerAddress
        );
        dao.setAddressConfiguration(
            _configKey(tokenAddr, FundTargetAddress),
            fundTargetAddress
        );
        dao.setConfiguration(
            _configKey(tokenAddr, ChunkSize), 
            chunkSize
        );
        dao.setConfiguration(
            _configKey(tokenAddr, UnitsPerChunk),
            unitsPerChunk
        );
        dao.setConfiguration(
            _configKey(tokenAddr, MaximumChunks),
            maximumChunks
        );
        dao.setConfiguration(
            _configKey(tokenAddr, MaximumUnits), 
            maxUnits
        );
        dao.setConfiguration(
            _configKey(tokenAddr, MaxMembers), 
            maxMembers
        );
        dao.setAddressConfiguration(
            _configKey(tokenAddr, TokensToMint),
            internalTokensToMint
        );

        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        bank.registerPotentialNewInternalToken(dao, DaoHelper.UNITS);
        bank.registerPotentialNewToken(dao, tokenAddr);
    }

    /**
     * @notice 将提供的 优惠券哈希为 ERC712 哈希 
     * @param dao 是要配置的 DAO 实例 
     * @param coupon 是要 散列 的优惠券
     */
    function hashCouponMessage(DaoRegistry dao, Coupon memory coupon)
        public
        view
        returns (bytes32)
    {
        bytes32 message = keccak256(
            abi.encode(COUPON_MESSAGE_TYPEHASH, coupon.kycedMember)
        );

        return hashMessage(dao, address(this), message);
    }

    /**
    * @notice 使用 ETH 加入 DAO 的 kyc 成员的入职流程 
    * @param kycedMember 想要加入 DAO 的 kyced 成员的地址 
    * @param signature 将被验证以兑换优惠券的签名
    */
    function onboardEth(
        DaoRegistry dao,
        address kycedMember,
        bytes memory signature
    ) external payable {
        _onboard(dao, kycedMember, DaoHelper.ETH_TOKEN, msg.value, signature);
    }

    /**
    * @notice 启动作为任何 ERC20 代币的 kyc 成员 加入 DAO 的入职流程
    * @param kycedMember 想要加入 DAO 的 kyced 成员的地址
    * @param tokenAddr 包含 kycedMember 资金的 ERC20 代币的地址
    * @param amount 将贡献给 DAO 以换取 DAO 单位的 ERC20 金额 
    * @param signature 将被验证以兑换优惠券的签名
    */
    function onboard(
        DaoRegistry dao,
        address kycedMember,
        address tokenAddr,
        uint256 amount,
        bytes memory signature
    ) external {
        _onboard(dao, kycedMember, tokenAddr, amount, signature);
    }

    /**
     * @notice 兑换优惠券以添加新成员 
     * @param dao 是要配置的 DAO 实例 
     * @param kycedMember 是该优惠券授权成为新成员的地址 
     * @param tokenAddr 是 ETH 地址（ 0 ) 或 ERC20 Token 地址 
     * @param signature 是用于验证的消息签名
     */
    function _onboard(
        DaoRegistry dao,
        address kycedMember,
        address tokenAddr,
        uint256 amount,
        bytes memory signature
    ) internal reimbursable(dao) {
        require(
            !isActiveMember(dao, dao.getCurrentDelegateKey(kycedMember)),
            "already member"
        );
        uint256 maxMembers = dao.getConfiguration(
            _configKey(tokenAddr, MaxMembers)
        );
        require(maxMembers > 0, "token not configured");
        require(dao.getNbMembers() < maxMembers, "the DAO is full");

        _checkKycCoupon(dao, kycedMember, tokenAddr, signature);

        OnboardingDetails memory details = _checkData(dao, tokenAddr, amount);
        totalUnits[dao][tokenAddr] += details.unitsRequested;

        BankExtension bank = BankExtension(dao.getExtensionAddress(DaoHelper.BANK));
        DaoHelper.potentialNewMember(kycedMember, dao, bank);

        address payable multisigAddress = payable(
            dao.getAddressConfiguration(
                _configKey(tokenAddr, FundTargetAddress)
            )
        );
        if (multisigAddress == address(0x0)) {
            if (tokenAddr == DaoHelper.ETH_TOKEN) {

                // 银行地址是从 DAO 注册表中加载的， 因此即使我们改变它，它也属于 DAO， 所以可以向它发送 eth。

                bank.addToBalance{value: details.amount}(dao, DaoHelper.GUILD, DaoHelper.ETH_TOKEN, details.amount);

            } else {
                bank.addToBalance(dao, DaoHelper.GUILD, tokenAddr, details.amount);
                
                IERC20 erc20 = IERC20(tokenAddr);
                erc20.safeTransferFrom(msg.sender, address(bank), details.amount);
            }
        } else {
            if (tokenAddr == DaoHelper.ETH_TOKEN) {
                // weth 地址是在合约部署期间定义的，一旦部署后就无法更改它， 所以发送 eth 给它就可以了。
                _weth.deposit{value: details.amount}();
                _weth20.safeTransferFrom(address(this), multisigAddress, details.amount);
            } else {
                IERC20 erc20 = IERC20(tokenAddr);
                erc20.safeTransferFrom(msg.sender, multisigAddress, details.amount);
            }
        }

        bank.addToBalance(dao, kycedMember, DaoHelper.UNITS, details.unitsRequested);

        if (amount > details.amount && tokenAddr == DaoHelper.ETH_TOKEN) {
            payable(msg.sender).sendValue(msg.value - details.amount);
        }

        emit Onboarded(dao, kycedMember, details.unitsRequested);
    }

    /**
     * @notice 验证给定的金额是否足以加入 DAO
     */
    function _checkData(
        DaoRegistry dao,
        address tokenAddr,
        uint256 amount
    ) internal view returns (OnboardingDetails memory details) {
        details.chunkSize = uint88(
            dao.getConfiguration(_configKey(tokenAddr, ChunkSize))
        );
        require(details.chunkSize > 0, "config chunkSize missing");
        details.numberOfChunks = uint88(amount / details.chunkSize);
        
        require(details.numberOfChunks > 0, "insufficient funds");
        require(
            details.numberOfChunks <= dao.getConfiguration(_configKey(tokenAddr, MaximumChunks)),
            "too much funds"
        );

        details.unitsPerChunk = uint88(
            dao.getConfiguration(_configKey(tokenAddr, UnitsPerChunk))
        );

        require(details.unitsPerChunk > 0, "config unitsPerChunk missing");
        details.amount = details.numberOfChunks * details.chunkSize;
        details.unitsRequested = details.numberOfChunks * details.unitsPerChunk;
        details.maximumTotalUnits = uint88(
            dao.getConfiguration(_configKey(tokenAddr, MaximumUnits))
        );

        require(
            details.unitsRequested + totalUnits[dao][tokenAddr] <= details.maximumTotalUnits,
            "over max total units"
        );
    }

    /**
      * @notice 检查给定的签名是否有效，如果有效，则允许会员 兑换 优惠券 并加入 DAO 
      * @param kycedMember 是此优惠券授权成为新会员的地址 
      * @param tokenAddr 是 ETH 地址（0）或 ERC20 Token 地址。 
      * @param signature 是消息签名，用于验证   
      */
    function _checkKycCoupon(
        DaoRegistry dao,
        address kycedMember,
        address tokenAddr,
        bytes memory signature
    ) internal view {
        require(
            ECDSA.recover(
                hashCouponMessage(dao, Coupon(kycedMember)),
                signature
            ) ==
                dao.getAddressConfiguration(
                    _configKey(tokenAddr, SignerAddressConfig)
                ),
            "invalid sig"
        );
    }

    /**
     * @notice 通过使用字符串键对 地址进行编码来构建 配置键  
     * @param tokenAddrToMint 要编码的地址
     * @param key 要编码的密钥
     */
    function _configKey(address tokenAddrToMint, bytes32 key)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(tokenAddrToMint, key));
    }
}
