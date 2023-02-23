// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../access_controller/PlatformAccessController.sol";
import "../token/price_provider/IPlatformTokenPriceProvider.sol";
import "../token/IplatformToken/IPlatformToken.sol";
import "../staking/IPlatformStaking/IPlatformStaking.sol";

/**
 * @title PlatformCashbackController
 * @notice Contract for cashback from st esrow payments
 * When user pay st tokens in STEscrow casback will be set
 * Cashback is the some share of st payments
 * User tier specify cashback share
 * Cashback sets during some time and only after that users can claim, this the one loop
 * When current loop finished next loop will be started
 * Every user have cashback limit for every loop
 * Casback balance must be less or equal then cashback limit on every loop
 * User tier specify cashback loop limit share
 */
contract PlatformCashbackController is PlatformAccessController {
    /**
     * @notice Emit during liquidity increasing
     * @param admin Admin who send transaction
     * @param amount PROP amount which will be transfer from `admin` to the contract
     */
    event IncreaseLiquidity(address indexed admin, uint256 amount);

    /**
     * @notice Emit during liquidity decreasing
     * @param admin Admin who send transaction
     * @param amount PROP amount which will be transfer from the contract to `admin`
     */
    event DecreaseLiquidity(address indexed admin, uint256 amount);

    /**
     * @notice Emit during fee property setting
     * @param admin Admin who send transaction
     * @param freeShare Cashback share from escrow payment for FREE tier users
     * @param starShare Cashback share from escrow payment for STAR tier users
     * @param moviShare Cashback share from escrow payment for MOVI tier users
     * @param moguShare Cashback share from escrow payment for MOGU tier users
     * @param tycoShare Cashback share from escrow payment for TYCO tier users
     */
    event SetShareProperties(
        address indexed admin,
        uint256 freeShare,
        uint256 starShare,
        uint256 moviShare,
        uint256 moguShare,
        uint256 tycoShare
    );

    /**
     * @notice Emit during limit property setting
     * @param admin Admin who send transaction
     * @param freeUsdLimit Cashback usd limit for FREE tier users during one loop
     * @param starUsdLimit Cashback usd limit for STAR tier users during one loop
     * @param moviUsdLimit Cashback usd limit for MOVI tier users during one loop
     * @param moguUsdLimit Cashback usd limit for MOGU tier users during one loop
     * @param tycoUsdLimit Cashback usd limit for TYCO tier users during one loop
     */
    event SetLimitProperties(
        address indexed admin,
        uint256 freeUsdLimit,
        uint256 starUsdLimit,
        uint256 moviUsdLimit,
        uint256 moguUsdLimit,
        uint256 tycoUsdLimit
    );

    /**
     * @notice Emit during loop properties set begining
     * @param admin Admin who send transaction
     * @param fromTick Start loop number
     * @param distributeStart Timemestamp from which distribution will be accessible
     * @param claimStart Timemestamp from which claim will be accessible
     * @param duration Distribution loop duration in seconds
     */
    event BeginSetLoopProperties(
        address indexed admin,
        uint256 fromTick,
        uint256 distributeStart,
        uint256 claimStart,
        uint256 duration
    );

    /**
     * @notice Emit during loop properties set breaking
     * @param admin Admin who send transaction
     */
    event BreakSetLoopProperties(address indexed admin);

    /**
     * @notice Emit during loop properties set completing
     */
    event CompleteSetLoopProperties();

    /**
     * @notice Emit during cashback distibution
     * @param wallet Cashback set to address
     * @param purchasePriceInUsd Purchase price in USD
     * @param addition Cashback USD amount what will be add to `wallet` cashback
     */
    event Distribute(
        address wallet,
        uint256 purchasePriceInUsd,
        uint256 addition
    );

    /**
     * @notice Emit during cashback claiming
     * @param wallet Cashback claim recipient address
     * @param amount Cashback PROP amount what will be send to `wallet`
     */
    event Claim(address wallet, uint256 amount);

    struct ShareProperties {
        uint256 freeShare;
        uint256 starShare;
        uint256 moviShare;
        uint256 moguShare;
        uint256 tycoShare;
    }

    struct LimitProperties {
        uint256 freeUsdLimit;
        uint256 starUsdLimit;
        uint256 moviUsdLimit;
        uint256 moguUsdLimit;
        uint256 tycoUsdLimit;
    }

    struct LoopProperties {
        uint256 distributeDuration;
        uint256 claimDuration;
    }

    struct Loop {
        uint256 fromTick;
        uint256 distributeStart;
        uint256 claimStart;
        uint256 duration;
    }

    uint256 private constant TOTAL_SHARE = 100_000;

    ShareProperties private _shares;
    LimitProperties private _limits;

    Loop private _loop;
    Loop private _nextLoop;

    mapping(address => uint256) private _claimFromTickMap;
    mapping(address => mapping(uint256 => uint256)) private _claimUsdMapping;

    address private _vesting;
    address private _staking;

    address private _token;
    address private _tokenPriceProvider;
    address private _escrow;

    modifier onlyEscrow() {
        require(_escrow == msgSender(), "sender is not escrow");
        _;
    }

    /**
     * @param adminPanel PlatformAdminPanel address
     */
    constructor(address adminPanel) {
        _initiatePlatformAccessController(adminPanel);
    }

    /**
     * @notice Initiate all internal params
     * Cashback distribution started alredy after this
     * Only platform admin can call
     * Can call only once
     * @param shareProperties ShareProperties
     * p.freeShare Cashback share from escrow payment for FREE tier users
     * p.starShare Cashback share from escrow payment for STAR tier users
     * p.moviShare Cashback share from escrow payment for MOVI tier users
     * p.moguShare Cashback share from escrow payment for MOGU tier users
     * p.tycoShare Cashback share from escrow payment for TYCO tier users
     * TOTAL_SHARE = 100_000 (100% = 100_000)
     * @param limitProperties LimitProperties
     * p.freeUsdLimit Cashback usd limit for FREE tier users during one loop
     * p.starUsdLimit Cashback usd limit for STAR tier users during one loop
     * p.moviUsdLimit Cashback usd limit for MOVI tier users during one loop
     * p.moguUsdLimit Cashback usd limit for MOGU tier users during one loop
     * p.tycoUsdLimit Cashback usd limit for TYCO tier users during one loop
     * @param loopProperties LoopProperties
     * p.distributeDuration One distribution loop duration in seconds
     * p.claimDuration Seconds which must spend after distribution to claim access
     */
    // OK
    function initiate(
        ShareProperties calldata shareProperties,
        LimitProperties calldata limitProperties,
        LoopProperties calldata loopProperties
    ) external onlyPlatformAdmin {
        _setShareProperties(shareProperties);
        _setLimitProperties(limitProperties);

        uint256 distributeStart = block.timestamp;
        uint256 claimStart = distributeStart +
            loopProperties.distributeDuration +
            loopProperties.claimDuration;
        uint256 duration = loopProperties.distributeDuration;

        require(0 < duration, "incorrect loop properties");

        Loop storage loop = _loop;
        loop.distributeStart = distributeStart;
        loop.claimStart = claimStart;
        loop.duration = duration;

        address admin = msgSender();
        emit BeginSetLoopProperties(
            admin,
            0,
            distributeStart,
            claimStart,
            duration
        );
        emit CompleteSetLoopProperties();
    }

    function updateTokenAddress(address token) external onlyPlatformAdmin {
        require(_token == address(0), "already initiated");
        require(token != address(0), "cant be zero address");

        _token = token;
    }

    function updateStakingAddress(address staking) external onlyPlatformAdmin {
        require(_staking == address(0), "already initiated");
        require(staking != address(0), "cant be zero address");

        _staking = staking;
    }

    function updateTokenPriceProviderAddress(address tokenPriceProvider)
        external
        onlyPlatformAdmin
    {
        require(_tokenPriceProvider == address(0), "already initiated");
        require(tokenPriceProvider != address(0), "cant be zero address");
        _tokenPriceProvider = tokenPriceProvider;
    }

    function updateEscrowAddress(address escrow) external onlyPlatformAdmin {
        require(_escrow == address(0), "already initiated");
        require(escrow != address(0), "cant be zero address");

        _escrow = escrow;
    }

    /**
     * @return liquidity PROP amount free for cashback claim payments
     */
    function liquidity() external view returns (uint256) {
        return IPlatformToken(_token).balanceOf(address(this));
    }

    /**
     * @return freeShare Cashback share from escrow payment for FREE tier users
     * @return starShare Cashback share from escrow payment for STAR tier users
     * @return moviShare Cashback share from escrow payment for MOVI tier users
     * @return moguShare Cashback share from escrow payment for MOGU tier users
     * @return tycoShare Cashback share from escrow payment for TYCO tier users
     */
    function getShareProperties()
        external
        view
        returns (
            uint256 freeShare,
            uint256 starShare,
            uint256 moviShare,
            uint256 moguShare,
            uint256 tycoShare
        )
    {
        ShareProperties storage shares = _shares;

        freeShare = shares.freeShare;
        starShare = shares.starShare;
        moviShare = shares.moviShare;
        moguShare = shares.moguShare;
        tycoShare = shares.tycoShare;
    }

    /**
     * @return freeUsdLimit Cashback usd limit for FREE tier users during one loop
     * @return starUsdLimit Cashback usd limit for STAR tier users during one loop
     * @return moviUsdLimit Cashback usd limit for MOVI tier users during one loop
     * @return moguUsdLimit Cashback usd limit for MOGU tier users during one loop
     * @return tycoUsdLimit Cashback usd limit for TYCO tier users during one loop
     */
    function getLimitProperties()
        external
        view
        returns (
            uint256 freeUsdLimit,
            uint256 starUsdLimit,
            uint256 moviUsdLimit,
            uint256 moguUsdLimit,
            uint256 tycoUsdLimit
        )
    {
        LimitProperties storage limits = _limits;

        freeUsdLimit = limits.freeUsdLimit;
        starUsdLimit = limits.starUsdLimit;
        moviUsdLimit = limits.moviUsdLimit;
        moguUsdLimit = limits.moguUsdLimit;
        tycoUsdLimit = limits.tycoUsdLimit;
    }

    /**
     * @notice Current loop properties
     * @return fromTick Start loop number
     * @return distributeStart Timemestamp from which distribution will be accessible
     * @return claimStart Timemestamp from which claim will be accessible
     * @return duration Distribution loop duration in seconds
     */
    function getLoopProperties()
        external
        view
        returns (
            uint256 fromTick,
            uint256 distributeStart,
            uint256 claimStart,
            uint256 duration
        )
    {
        Loop storage loop = _loop;

        fromTick = loop.fromTick;
        distributeStart = loop.distributeStart;
        claimStart = loop.claimStart;
        duration = loop.duration;
    }

    /**
     * @notice Next loop properties
     * If last loop properties set was complite all params will be empty
     * @return fromTick Start loop number
     * @return distributeStart Timemestamp from which distribution will be accessible
     * @return claimStart Timemestamp from which claim will be accessible
     * @return duration Distribution loop duration in seconds
     */
    function getNextLoopProperties()
        external
        view
        returns (
            uint256 fromTick,
            uint256 distributeStart,
            uint256 claimStart,
            uint256 duration
        )
    {
        Loop storage loop = _nextLoop;

        fromTick = loop.fromTick;
        distributeStart = loop.distributeStart;
        claimStart = loop.claimStart;
        duration = loop.duration;
    }

    /**
     * @notice If user cashback balance empty for all loops return zero
     * @param wallet User address
     * @param time Now timestamp is seconds
     * @return timeForClaim Timestamp from which user can claim cashback
     */
    function timeForClaim(address wallet, uint256 time)
        external
        view
        returns (uint256)
    {
        (bool isBegin, uint256 toTick) = _distributeTick(time);
        if (!isBegin) {
            return 0;
        }

        mapping(uint256 => uint256) storage map = _claimUsdMapping[wallet];
        Loop storage n = _nextLoop;
        Loop storage c = _loop;

        uint256 fromTick = _claimFromTickMap[wallet];
        for (uint256 tick = fromTick; tick <= toTick; tick++) {
            if (map[tick] == 0) {
                continue;
            }
            if (0 < n.duration && n.fromTick <= tick) {
                return n.claimStart + n.duration * (tick - n.fromTick);
            }

            if (0 < c.duration && c.fromTick <= tick) {
                return c.claimStart + c.duration * (tick - c.fromTick);
            }
        }

        return 0;
    }

    /**
     * @param wallet User address
     * @param time Now timestamp is seconds
     * @return amountForClaim Amount which user can claim from `time`
     */
    function amountForClaim(address wallet, uint256 time)
        external
        view
        returns (uint256)
    {
        (bool isBegin, uint256 toTick) = _claimTick(time);
        if (!isBegin) {
            return 0;
        }

        uint256 usd;
        uint256 fromTick = _claimFromTickMap[wallet];
        mapping(uint256 => uint256) storage map = _claimUsdMapping[wallet];
        for (uint256 tick = fromTick; tick <= toTick; tick++) {
            usd += map[tick];
        }

        return _usdToToken(usd);
    }

    /**
     * @notice Increase free for cashback claim PROP amount
     * Only platform admin can call
     * @param amount PROP amount which will be transfer from sender to the contract
     */
    function increaseLiquidity(
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyPlatformAdmin {
        require(0 < amount, "incorrect input");

        address admin = msgSender();

        IPlatformToken(_token).specialTransferFrom(
            admin,
            amount,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        emit IncreaseLiquidity(admin, amount);
    }

    /**
     * @notice Decrease free for cashback claim PROP amount
     * Only platform admin can call
     * @param amount PROP amount which will be transfer from the contract to sender
     */
    function decreaseLiquidity(uint256 amount) external onlyPlatformAdmin {
        require(0 < amount, "incorrect input");

        address admin = msgSender();

        IPlatformToken(_token).transfer(admin, amount);

        emit DecreaseLiquidity(admin, amount);
    }

    /**
     * @notice Reset fee properties
     * Only platform admin can call
     * @param p ShareProperties
     * p.freeShare Cashback share from escrow payment for FREE tier users
     * p.starShare Cashback share from escrow payment for STAR tier users
     * p.moviShare Cashback share from escrow payment for MOVI tier users
     * p.moguShare Cashback share from escrow payment for MOGU tier users
     * p.tycoShare Cashback share from escrow payment for TYCO tier users
     * TOTAL_SHARE = 100_000 (100% = 100_000)
     */
    function setShareProperties(ShareProperties calldata p)
        external
        onlyPlatformAdmin
    {
        _setShareProperties(p);
    }

    /**
     * @notice Reset limit properties
     * Only platform admin can call
     * @param p LimitProperties
     * p.freeUsdLimit Cashback usd limit for FREE tier users during one loop
     * p.starUsdLimit Cashback usd limit for STAR tier users during one loop
     * p.moviUsdLimit Cashback usd limit for MOVI tier users during one loop
     * p.moguUsdLimit Cashback usd limit for MOGU tier users during one loop
     * p.tycoUsdLimit Cashback usd limit for TYCO tier users during one loop
     */
    function setLimitProperties(LimitProperties calldata p)
        external
        onlyPlatformAdmin
    {
        _setLimitProperties(p);
    }

    /**
     * @notice Begin loop properties reset process
     * Only platform admin can call
     * New loop will be start from previous loop distribution end
     * Need: previous loop properties reset must be comlited
     * Need: previous loop claim duration <= p.distributeDuration + p.claimDuration
     * @param p LoopProperties
     * p.distributeDuration One distribution loop duration in seconds
     * p.claimDuration Seconds which must spend after distribution to claim access
     */
    function beginSetLoopProperties(LoopProperties calldata p)
        external
        onlyPlatformAdmin
    {
        Loop storage n = _nextLoop;
        require(
            n.distributeStart == 0 || n.distributeStart < block.timestamp,
            "distribute start already"
        );

        (bool isBegin, uint256 tick) = _distributeTick(block.timestamp);
        require(isBegin, "CashbackError: unexpected tick");

        Loop storage c = _loop;
        uint256 fromTick = 1 + tick;
        uint256 distributeStart = c.distributeStart +
            c.duration *
            (fromTick - c.fromTick);
        uint256 claimStart = distributeStart +
            p.distributeDuration +
            p.claimDuration;
        uint256 duration = p.distributeDuration + p.claimDuration;

        require(
            0 < p.distributeDuration &&
                c.claimStart - c.distributeStart - c.duration <= duration,
            "incorrect loop properties"
        );

        n.fromTick = fromTick;
        n.distributeStart = distributeStart;
        n.claimStart = claimStart;
        n.duration = duration;

        address admin = msgSender();
        emit BeginSetLoopProperties(
            admin,
            fromTick,
            distributeStart,
            claimStart,
            duration
        );
    }

    /**
     * @notice Break loop properties reset process
     * Only platform admin can call
     * Need: previous loop properties reset must not be comlited
     */
    function breakSetLoopProperties() external onlyPlatformAdmin {
        Loop storage n = _nextLoop;
        require(
            n.distributeStart == 0 || n.distributeStart < block.timestamp,
            "distribute start already"
        );

        n.fromTick = 0;
        n.distributeStart = 0;
        n.claimStart = 0;
        n.duration = 0;

        address admin = msgSender();
        emit BreakSetLoopProperties(admin);
    }

    /**
     * @dev Increase user cashback claim amount
     * Function for interaction between platform contracts
     * @param wallet User address
     * @param purchasePriceInUsd Purchase price in USD
     */
    function distribute(address wallet, uint256 purchasePriceInUsd)
        external
        onlyEscrow
    {
        _completeSetLoopProperties();

        uint256 time = block.timestamp;
        (uint256 fee, uint256 limit) = _userTierProperties(wallet, time);
        if (fee == 0 || limit == 0) {
            return;
        }

        (bool isBegin, uint256 tick) = _distributeTick(time);
        require(isBegin, "CashbackError: unexpected tick");

        uint256 usd = _claimUsdMapping[wallet][tick];
        if (usd == limit) {
            return;
        }

        uint256 addition = _share(purchasePriceInUsd, fee);
        if (limit < usd + addition) {
            addition = limit - usd;
        }

        _claimUsdMapping[wallet][tick] = usd + addition;

        emit Distribute(wallet, purchasePriceInUsd, addition);
    }

    /**
     * @notice Claim user cashback amount
     * Transfer PROP cashback amount from the contract to user
     * If liquidity less then cashback amount will be revert
     * @param wallet User address
     */
    function claim(address wallet) external {
        _completeSetLoopProperties();

        (bool isBegin, uint256 toTick) = _claimTick(block.timestamp);
        require(isBegin, "claim not started yet");

        uint256 fromTick = _claimFromTickMap[wallet];
        _claimFromTickMap[wallet] = 1 + toTick;

        uint256 totalUsd;
        mapping(uint256 => uint256) storage map = _claimUsdMapping[wallet];
        for (uint256 tick = fromTick; tick <= toTick; tick++) {
            uint256 usd = map[tick];
            if (usd == 0) {
                continue;
            }

            delete map[tick];

            totalUsd += usd;
        }

        uint256 amount = _usdToToken(totalUsd);

        require(0 < amount, "insufficient funds");

        IPlatformToken(_token).transfer(wallet, amount);

        emit Claim(wallet, amount);
    }

    function _share(uint256 amount, uint256 share)
        private
        pure
        returns (uint256)
    {
        return (amount * share) / TOTAL_SHARE;
    }

    function _usdToToken(uint256 amount) private view returns (uint256) {
        IPlatformTokenPriceProvider provider = IPlatformTokenPriceProvider(
            _tokenPriceProvider
        );

        return provider.tokenAmount(amount);
    }

    function _userTierProperties(address wallet, uint256 time)
        private
        view
        returns (uint256 fee, uint256 limit)
    {
        (UserTier tier, bool isTierTurnOn) = IPlatformStaking(_staking)
            .userTier(wallet, time);

        if (!isTierTurnOn || tier == UserTier.FREE) {
            return (_shares.freeShare, _limits.freeUsdLimit);
        }
        if (tier == UserTier.STAR) {
            return (_shares.starShare, _limits.starUsdLimit);
        }
        if (tier == UserTier.MOVI) {
            return (_shares.moviShare, _limits.moviUsdLimit);
        }
        if (tier == UserTier.MOGU) {
            return (_shares.moguShare, _limits.moguUsdLimit);
        }
        if (tier == UserTier.TYCO) {
            return (_shares.tycoShare, _limits.tycoUsdLimit);
        }

        revert("CashbackError: unexpected tier");
    }

    function _distributeTick(uint256 time)
        private
        view
        returns (bool, uint256)
    {
        Loop storage n = _nextLoop;
        if (0 < n.distributeStart && n.distributeStart <= time) {
            uint256 tick = n.fromTick + (time - n.distributeStart) / n.duration;
            return (true, tick);
        }

        Loop storage c = _loop;
        if (0 < c.distributeStart && c.distributeStart <= time) {
            uint256 tick = c.fromTick + (time - c.distributeStart) / c.duration;
            return (true, tick);
        }

        return (false, 0);
    }

    function _claimTick(uint256 time) private view returns (bool, uint256) {
        Loop storage n = _nextLoop;
        if (0 < n.claimStart && n.claimStart <= time) {
            uint256 tick = n.fromTick + (time - n.claimStart) / n.duration;
            return (true, tick);
        }

        Loop storage c = _loop;
        if (0 < c.claimStart && c.claimStart <= time) {
            uint256 tick = c.fromTick + (time - c.claimStart) / c.duration;
            return (true, tick);
        }

        return (false, 0);
    }

    /**
     * @dev sums all the of shares to make sure it adds up to TOTAL_SHARE
     * @param p this is a Share Properties data with all the details for the sum
     **/
    function sumOfShares(ShareProperties calldata p)
        internal
        pure
        returns (uint256 total)
    {
        return
            p.freeShare + p.starShare + p.moviShare + p.moguShare + p.tycoShare;
    }

    function _setShareProperties(ShareProperties calldata p) private {
        uint256 totalSum = sumOfShares(p);
        require(totalSum == TOTAL_SHARE, " incorrect share values ");
        require(
            p.freeShare <= p.starShare &&
                p.starShare <= p.moviShare &&
                p.moviShare <= p.moguShare &&
                p.moguShare <= p.tycoShare &&
                p.tycoShare <= TOTAL_SHARE,
            "incorrect fee properties"
        );

        ShareProperties storage shares = _shares;

        shares.freeShare = p.freeShare;
        shares.starShare = p.starShare;
        shares.moviShare = p.moviShare;
        shares.moguShare = p.moguShare;
        shares.tycoShare = p.tycoShare;

        address admin = msgSender();
        emit SetShareProperties(
            admin,
            p.freeShare,
            p.starShare,
            p.moviShare,
            p.moguShare,
            p.tycoShare
        );
    }

    function _setLimitProperties(LimitProperties calldata p) private {
        require(
            p.freeUsdLimit <= p.starUsdLimit &&
                p.starUsdLimit <= p.moviUsdLimit &&
                p.moviUsdLimit <= p.moguUsdLimit &&
                p.moguUsdLimit <= p.tycoUsdLimit,
            "incorrect limit properties"
        );

        LimitProperties storage limits = _limits;

        limits.freeUsdLimit = p.freeUsdLimit;
        limits.starUsdLimit = p.starUsdLimit;
        limits.moviUsdLimit = p.moviUsdLimit;
        limits.moguUsdLimit = p.moguUsdLimit;
        limits.tycoUsdLimit = p.tycoUsdLimit;

        address admin = msgSender();
        emit SetLimitProperties(
            admin,
            p.freeUsdLimit,
            p.starUsdLimit,
            p.moviUsdLimit,
            p.moguUsdLimit,
            p.tycoUsdLimit
        );
    }

    function _completeSetLoopProperties() private {
        Loop storage n = _nextLoop;
        if (n.claimStart < block.timestamp) {
            return;
        }

        Loop storage c = _loop;

        c.fromTick = n.fromTick;
        c.distributeStart = n.distributeStart;
        c.claimStart = n.claimStart;
        c.duration = n.duration;

        n.fromTick = 0;
        n.distributeStart = 0;
        n.claimStart = 0;
        n.duration = 0;

        emit CompleteSetLoopProperties();
    }
}
