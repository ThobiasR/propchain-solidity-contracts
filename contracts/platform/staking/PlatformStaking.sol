// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../access_controller/PlatformAccessController.sol";
import "../token/IplatformToken/IPlatformToken.sol";
import "../token/price_provider/IPlatformTokenPriceProvider.sol";
import "../vesting/IPlatformVesting/IPlatformVesting.sol";

enum UserTier {
    FREE,
    STAR,
    MOVI,
    MOGU,
    TYCO
}

/**
 * @notice Required to get user tier as access to the platform functionality
 */
contract PlatformStaking is PlatformAccessController {
    /**
     * @notice Emit when user stake
     * @param wallet User wallet address
     * @param toTier User tier after stake
     * @param vestingAmount PROP amount stake from vesting
     * @param walletAmount PROP amount stake from user wallet
     * @param fee Stake fee amount
     */
    event Stake(
        address indexed wallet,
        UserTier toTier,
        uint256 vestingAmount,
        uint256 walletAmount,
        uint256 fee
    );

    /**
     * @notice Emit when user unstake
     * @param wallet User wallet address
     */
    event Unstake(address indexed wallet);

    /**
     * @notice Emit when admin set stake limits for tiers
     * @param admin Platform admin which do this action
     */
    event SetTierProperties(
        address indexed admin,
        uint256 starAmount,
        uint256 moviAmount,
        uint256 moguAmount,
        uint256 tycoAmount
    );

    /**
     * @notice Emit when admin set stake fee share
     * @param admin Platform admin which do this action
     */
    event SetFeeShare(address indexed admin, uint256 share);

    /**
     * @notice Emit when admin set stake lock time
     * @param admin Platform admin which do this action
     */
    event SetLockTime(address indexed admin, uint256 lockTime);

    /**
     * @notice Emit when admin withdraw stake fee amount
     * @param admin Platform admin which do this action
     */
    event Withdraw(address indexed admin, uint256 amount);

    struct UserProperties {
        UserTier tier;
        uint256 unlockTime;
        uint256 walletStakeAmount;
        uint256 vestingStakeAmount;
    }

    uint256 private constant TOTAL_SHARE = 100_000;

    uint256 public _requireStarAmount;
    uint256 public _requireMoviAmount;
    uint256 public _requireMoguAmount;
    uint256 public _requireTycoAmount;

    uint256 public _feeTotalAmount;
    uint256 public _feeShare;

    uint256 public _lockTime;

    address private _vesting;
    address private _token;
    address private _tokenPriceProvider;

    mapping(address => UserProperties) public _userMap;

    constructor(
        address adminPanel_,
        uint256 requireUsdAmountForStarTier_,
        uint256 requireUsdAmountForMoviTier_,
        uint256 requireUsdAmountForMoguTier_,
        uint256 requireUsdAmountForTycoTier_,
        uint256 stakeFeeShare_,
        uint256 stakeLockTimeInSeconds_
    ) {
        _initiatePlatformAccessController(adminPanel_);

        _setTierProperties(
            requireUsdAmountForStarTier_,
            requireUsdAmountForMoviTier_,
            requireUsdAmountForMoguTier_,
            requireUsdAmountForTycoTier_
        );

        _setFeeShare(stakeFeeShare_);

        _setLockTime(stakeLockTimeInSeconds_);
    }

    /**
     * @notice Removed the initiate function as recommended and craeted various setters
     */
    function updateVestingAddress(address vesting) external onlyPlatformAdmin {
        require(_vesting == address(0), "already initiated");
        require(vesting != address(0), "cant be zero address");
        _vesting = vesting;
    }

    function updateTokenAddress(address token) external onlyPlatformAdmin {
        require(_token == address(0), "already initiated");
        require(token != address(0), "cant be zero address");
        _token = token;
    }

    function updateTokenPriceProviderAddress(address tokenPriceProvider)
        external
        onlyPlatformAdmin
    {
        require(_tokenPriceProvider == address(0), "already initiated");
        require(tokenPriceProvider != address(0), "cant be zero address");

        _tokenPriceProvider = tokenPriceProvider;
    }

    /**
     * @dev Amount of staked missing dollars required to get a certain tier
     */
    function tierProperties()
        external
        view
        returns (
            uint256 requireUsdAmountForStarTier,
            uint256 requireUsdAmountForMoviTier,
            uint256 requireUsdAmountForMoguTier,
            uint256 requireUsdAmountForTycoTier
        )
    {
        requireUsdAmountForStarTier = _requireStarAmount;
        requireUsdAmountForMoviTier = _requireMoviAmount;
        requireUsdAmountForMoguTier = _requireMoguAmount;
        requireUsdAmountForTycoTier = _requireTycoAmount;
    }

    /**
     * @notice User properties
     * @param wallet User wallet address
     * @return tier User tier after stake
     * @return unlockTimestampInSeconds Staking expiration time
     * @return walletStakeAmount PROP amount stake from user wallet
     * @return vestingStakeAmount Total PROP amount stake from vesting
     * @param vestingStakeAmountList  PROP amount stake from all vesting list
     */
    function userProperties(address wallet)
        external
        view
        returns (
            UserTier tier,
            uint256 unlockTimestampInSeconds,
            uint256 walletStakeAmount,
            uint256 vestingStakeAmount,
            uint256[] memory vestingStakeAmountList
        )
    {
        UserProperties storage user = _userMap[wallet];

        tier = user.tier;
        unlockTimestampInSeconds = user.unlockTime;
        walletStakeAmount = user.walletStakeAmount;
        vestingStakeAmount = user.vestingStakeAmount;

        vestingStakeAmountList = IPlatformVesting(_vesting).stakeAmountList(
            wallet
        );
    }

    /**
     * @notice User tier
     * @param wallet User wallet address
     * @param timestampInSeconds Now moment
     * @return tier User tier after stake
     * @return isTierTurnOn Staking is expirate
     */
    function userTier(address wallet, uint256 timestampInSeconds)
        external
        view
        returns (UserTier tier, bool isTierTurnOn)
    {
        UserProperties storage user = _userMap[wallet];

        tier = user.tier;
        isTierTurnOn =
            tier == UserTier.FREE ||
            timestampInSeconds < user.unlockTime;
    }

    /**
     * @notice Amount of PROP needed to go from `fromTier` to `toTier`
     */
    function requireStakeAmount(UserTier fromTier, UserTier toTier)
        external
        view
        returns (uint256)
    {
        return _requireStakeAmount(fromTier, toTier);
    }

    /**
     * @notice Amount of PROP needed for user to `toTier`
     */
    function requireStakeAmount(address wallet, UserTier toTier)
        external
        view
        returns (uint256)
    {
        UserProperties storage user = _userMap[wallet];
        return _requireStakeAmount(user.tier, toTier);
    }

    /**
     * @dev Only admin contract can do
     */
    function setTierProperties(
        uint256 requireUsdAmountForStarTier,
        uint256 requireUsdAmountForMoviTier,
        uint256 requireUsdAmountForMoguTier,
        uint256 requireUsdAmountForTycoTier
    ) external onlyPlatformAdmin {
        _setTierProperties(
            requireUsdAmountForStarTier,
            requireUsdAmountForMoviTier,
            requireUsdAmountForMoguTier,
            requireUsdAmountForTycoTier
        );
    }

    /**
     * @dev Only admin contract can do
     */
    function setStakeFeeShare(uint256 share) external onlyPlatformAdmin {
        _setFeeShare(share);
    }

    /**
     * @dev Only admin contract can do
     */
    function setStakeLockTime(uint256 timeInSeconds)
        external
        onlyPlatformAdmin
    {
        _setLockTime(timeInSeconds);
    }

    /**
     * @dev Transfers to the sender all the accumulated amount of stake fee
     * Only admin contract can do
     */
    function withdraw() external onlyPlatformAdmin {
        uint256 amount = _feeTotalAmount;
        require(0 < amount, "insufficient funds");

        address admin = msgSender();

        _feeTotalAmount = 0;
        _transferTo(admin, amount);

        emit Withdraw(admin, amount);
    }

    function _stake(
        UserTier toTier,
        uint256[] memory vestingAmountList,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        address wallet = msgSender();
        UserProperties storage user = _userMap[wallet];

        uint256 unlockTime = user.unlockTime;

        require(
            unlockTime == 0 || block.timestamp < unlockTime,
            "stake lock is ended"
        );

        uint256 feeShare = _feeShare;
        uint256 totalShare = TOTAL_SHARE;

        uint256 vestingAmount;
        uint256 vestingFeeAmount;

        uint256 index = vestingAmountList.length;

        if (0 < index) {
            require(
                index <= IPlatformVesting(_vesting).getVestingCount(),
                "PV: amounts more than vestingsd"
            );

            while (0 < index) {
                --index;
                uint256 amount = vestingAmountList[index];

                if (amount == 0) {
                    continue;
                }

                uint256 fee = IPlatformVesting(_vesting)._stake(
                    index,
                    wallet,
                    amount,
                    feeShare,
                    totalShare
                );

                vestingAmount += amount - fee;
                vestingFeeAmount += fee;
            }

            require(0 < vestingAmount, "PV: no contract changes");
        }

        (
            uint256 walletAmount,
            uint256 walletFeeAmount,
            uint256 tfamount
        ) = _walletStake(
                user.tier,
                toTier,
                vestingAmount + vestingFeeAmount,
                feeShare,
                totalShare
            );

        _transferFrom(
            wallet,
            tfamount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        user.tier = toTier;

        user.unlockTime = block.timestamp + _lockTime;

        if (0 < vestingAmount) {
            user.vestingStakeAmount += vestingAmount;
        }

        if (0 < walletAmount) {
            user.walletStakeAmount += walletAmount;
        }

        if (0 < walletFeeAmount) {
            _feeTotalAmount += walletFeeAmount;
        }

        emit Stake(
            wallet,
            toTier,
            vestingAmount,
            walletAmount,
            walletFeeAmount + vestingFeeAmount
        );
    }

    /**
     * @dev Stake of all funds
     * Vesting from the wallet is returned to the wallet
     * Vesting is simply unlocked
     * Available after the expiration of the staking lock
     */
    function unstake() external {
        address wallet = msgSender();

        UserProperties storage user = _userMap[wallet];
        require(user.unlockTime <= block.timestamp, "stake lock is not ended");

        uint256 vestingAmount = user.vestingStakeAmount;
        uint256 walletAmount = user.walletStakeAmount;

        require(0 < vestingAmount || 0 < walletAmount, "no staked funds");

        delete _userMap[wallet];

        if (0 < vestingAmount) {
            uint256 amount = IPlatformVesting(_vesting).unstake(wallet);
            require(amount == vestingAmount, "error - vesting unstake");
        }

        if (0 < walletAmount) {
            _transferTo(wallet, walletAmount);
        }

        emit Unstake(wallet);
    }

    function _amountShare(
        uint256 amount,
        uint256 share,
        uint256 total
    ) private pure returns (uint256) {
        return (amount * share) / total;
    }

    function _requireStakeAmount(UserTier fromTier, UserTier toTier)
        private
        view
        returns (uint256)
    {
        uint256 fromUsdAmount = _tierUsdAmount(fromTier);
        uint256 toUsdAmount = _tierUsdAmount(toTier);

        require(fromUsdAmount < toUsdAmount, "incorrect tier up");

        IPlatformTokenPriceProvider provider = IPlatformTokenPriceProvider(
            _tokenPriceProvider
        );
        return provider.tokenAmount(toUsdAmount - fromUsdAmount);
    }

    function _tierUsdAmount(UserTier tier) private view returns (uint256) {
        if (tier == UserTier.STAR) {
            return _requireStarAmount;
        }
        if (tier == UserTier.MOVI) {
            return _requireMoviAmount;
        }
        if (tier == UserTier.MOGU) {
            return _requireMoguAmount;
        }
        if (tier == UserTier.TYCO) {
            return _requireTycoAmount;
        }

        return 0;
    }

    function _setTierProperties(
        uint256 starAmount,
        uint256 moviAmount,
        uint256 moguAmount,
        uint256 tycoAmount
    ) private {
        require(
            0 < starAmount &&
                starAmount < moviAmount &&
                moviAmount < moguAmount &&
                moguAmount < tycoAmount,
            "incorrect tier properties"
        );

        _requireStarAmount = starAmount;
        _requireMoviAmount = moviAmount;
        _requireMoguAmount = moguAmount;
        _requireTycoAmount = tycoAmount;

        emit SetTierProperties(
            msgSender(),
            starAmount,
            moviAmount,
            moguAmount,
            tycoAmount
        );
    }

    function _setFeeShare(uint256 share) private {
        require(share < TOTAL_SHARE, "incorrect share");
        _feeShare = share;

        emit SetFeeShare(msgSender(), share);
    }

    function _setLockTime(uint256 lockTime) private {
        require(0 < lockTime, "incorrect lock time");
        _lockTime = lockTime;

        emit SetLockTime(msgSender(), lockTime);
    }

    function _walletStake(
        UserTier fromTier,
        UserTier toTier,
        uint256 vestingAmount,
        uint256 feeShare,
        uint256 totalShare
    )
        private
        view
        returns (
            uint256 walletAmount,
            uint256 walletFeeAmount,
            uint256 amount
        )
    {
        uint256 requireAmount = _requireStakeAmount(fromTier, toTier);

        if (requireAmount <= vestingAmount) {
            return (0, 0, 0);
        }

        amount = requireAmount - vestingAmount;

        walletFeeAmount = _amountShare(amount, feeShare, totalShare);
        walletAmount = amount - walletFeeAmount;
    }

    function _transferFrom(
        address from,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private {
        IPlatformToken(_token).specialTransferFrom(
            from,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    function _transferTo(address to, uint256 amount) private {
        IPlatformToken(_token).transfer(to, amount);
    }
}
