pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../core/DaoRegistry.sol";
import "../extensions/bank/Bank.sol";
import "../guards/AdapterGuard.sol";
import "./modifiers/Reimbursable.sol";
import "../utils/Signatures.sol";
import "../helpers/DaoHelper.sol";

// 1. 检查优惠券是否尚未兑换
// 2. 检查签名哈希是否与兑换参数的哈希匹配
// 3. 检查优惠券的签名者是否与配置的签名者匹配
// 4. 将配置的令牌铸造给新成员
// 5. 标记已兑换的优惠券
contract CouponOnboardingContract is Reimbursable, AdapterGuard, Signatures {
    struct Coupon {
        address authorizedMember;
        uint256 amount;
        uint256 nonce;
    }

    using SafeERC20 for IERC20;

    string public constant COUPON_MESSAGE_TYPE = "Message(address authorizedMember,uint256 amount,uint256 nonce)";
    bytes32 public constant COUPON_MESSAGE_TYPEHASH = keccak256(abi.encodePacked(COUPON_MESSAGE_TYPE));

    bytes32 constant SignerAddressConfig = keccak256("coupon-onboarding.signerAddress");
    bytes32 constant TokenAddrToMint = keccak256("coupon-onboarding.tokenAddrToMint");

    bytes32 constant ERC20InternalTokenAddr = keccak256("coupon-onboarding.erc20.internal.token.address");

    // dao addr --> flag id --> flag value
    mapping(address => mapping(uint256 => uint256)) private _flags;

    // 优惠券已兑换
    event CouponRedeemed(
        address daoAddress,
        uint256 nonce,
        address authorizedMember,
        uint256 amount
    );

    /**
     * @notice 使用优惠券签名者地址和要铸造的令牌配置适配器 
     * @param signerAddress 优惠券签名者的地址 
     * @param erc20 用于发行股票的内部 ERC20 代币的地址
     * @param tokenAddrToMint 用于 铸造优惠券 的代币地址
     * @param maxAmount 用于铸造的最大优惠券数量
     */
    function configureDao(
        DaoRegistry dao,
        address signerAddress,
        address erc20,
        address tokenAddrToMint,
        uint88 maxAmount
    ) external onlyAdapter(dao) {
        dao.setAddressConfiguration(SignerAddressConfig, signerAddress);
        dao.setAddressConfiguration(ERC20InternalTokenAddr, erc20);
        dao.setAddressConfiguration(TokenAddrToMint, tokenAddrToMint);

        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        bank.registerPotentialNewInternalToken(dao, tokenAddrToMint);

        uint160 currentBalance = bank.balanceOf(
            DaoHelper.TOTAL,
            tokenAddrToMint
        );
        if (currentBalance < maxAmount) {
            bank.addToBalance(
                dao,
                DaoHelper.GUILD,
                tokenAddrToMint,
                maxAmount - currentBalance
            );
        }
    }

    /**
     * @notice 将提供的 优惠券哈希 为 ERC712 哈希 
     * @param dao 是要配置的 DAO 实例 
     * @param coupon 是要散列的优惠券
     */
    function hashCouponMessage(DaoRegistry dao, Coupon memory coupon)
        public
        view
        returns (bytes32)
    {
        bytes32 message = keccak256(
            abi.encode(COUPON_MESSAGE_TYPEHASH, coupon.authorizedMember, coupon.amount, coupon.nonce)
        );

        return hashMessage(dao, address(this), message);
    }

    /**
     * @notice 兑换 优惠券 以添加新成员
     * @param dao 是要配置的 DAO 实例 
     * @param authorizedMember 被授权成为 新会员的地址 
     * @param amount 此会员 将收到的 units 数量 
     * @param nonce 唯一标识符 
     * @param signature 签名是用于验证的消息签名
     */
    function redeemCoupon(
        DaoRegistry dao,
        address authorizedMember,
        uint256 amount,
        uint256 nonce,
        bytes memory signature
    ) external reimbursable(dao) {
        {
            uint256 currentFlag = _flags[address(dao)][nonce / 256];

            _flags[address(dao)][nonce / 256] = DaoHelper.setFlag(currentFlag, nonce % 256, true);

            require(
                DaoHelper.getFlag(currentFlag, nonce % 256) == false,
                "coupon already redeemed"
            );
        }

        Coupon memory coupon = Coupon(authorizedMember, amount, nonce);
        bytes32 hash = hashCouponMessage(dao, coupon);

        require(
            SignatureChecker.isValidSignatureNow(
                dao.getAddressConfiguration(SignerAddressConfig),
                hash,
                signature
            ),
            "invalid sig"
        );

        IERC20 erc20 = IERC20(
            dao.getAddressConfiguration(ERC20InternalTokenAddr)
        );
        BankExtension bank = BankExtension(
            dao.getExtensionAddress(DaoHelper.BANK)
        );
        if (address(erc20) == address(0x0)) {
            address tokenAddressToMint = dao.getAddressConfiguration(TokenAddrToMint);

            // from : DaoHelper.GUILD
            // to: authorizedMember
            // token: tokenAddressToMint
            bank.internalTransfer(dao, DaoHelper.GUILD, authorizedMember, tokenAddressToMint, amount);

            // 地址需要添加到 成员映射中。 ERC20 正在为我们做这件事， 所以不需要做两次
            DaoHelper.potentialNewMember(authorizedMember, dao, bank);
        } else {
            erc20.safeTransferFrom(DaoHelper.GUILD, authorizedMember, amount);
        }

        emit CouponRedeemed(address(dao), nonce, authorizedMember, amount);
    }
}
