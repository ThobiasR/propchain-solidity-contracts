// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../access_controller/PlatformAccessController.sol";
import "../token/IplatformToken/IPlatformToken.sol";

/**
 * @notice Separate vesting pool, each with separate liquidity, whitelists and parameters
 */
contract PlatformVesting is PlatformAccessController {
    event InsertVestingList(address indexed admin, uint256 vestingCount);

    /**
     * @notice Emit during vesting vesting liquidity increasing
     * Liquidity of the vesting decreases
     * @param admin Platform admin which do this action
     * @param vestingId The vesting id
     * @param amount The PROP token amount which add to vesting free amount
     */
    event IncreaseLiquidity(
        address indexed admin,
        uint256 indexed vestingId,
        uint256 amount
    );

    /**
     * @notice Emit during vesting vesting liquidity decreasing process
     * Liquidity of the vesting increases
     * @param admin Platform admin which do this action
     * @param vestingId The vesting id
     * @param amount The PROP token amount which rem from vesting free amount
     */
    event DecreaseLiquidity(
        address indexed admin,
        uint256 indexed vestingId,
        uint256 amount
    );

    event InsertWalletListToVesting(
        address indexed admin,
        uint256 indexed vestingId,
        address[] walletList
    );

    event RemoveWalletListFromVesting(
        address indexed admin,
        uint256 indexed vestingId,
        address[] walletList
    );

    /**
     * @notice Emit when user claim his PROP from vesting
     * @param vestingId The vesting id
     * @param wallet The user wallet
     * @param amount The PROP token amount which user save
     */
    event Claim(
        uint256 indexed vestingId,
        address indexed wallet,
        uint256 amount
    );

    struct VestingProperties {
        bool isStakeSupport;
        uint256 amountForUser;
        uint256 tgeAmountForUser;
        uint256 startTime;
        uint256 tickCount;
        uint256 tickDuration;
        uint256 unallocateAmount;
    }

    struct UserProperties {
        bool isActive;
        uint256 spentAmount;
        uint256 stakeAmount;
    }

    uint256 private constant TOTAL_SHARE = 100_000;

    uint256 private constant MAX_VESTING_COUNT = 64;

    uint256 private tgeStartDate;
    address private _token;
    address private _staking;

    uint256 public _vestingCount;

    mapping(uint256 => VestingProperties) private _vestingMap;

    mapping(address => mapping(uint256 => UserProperties)) private _userMapping;

    modifier existingVesting(uint256 vestingId) {
        require(vestingId < _vestingCount, "vesting is not exist for id");
        _;
    }

    modifier onlyStaking() {
        require(msgSender() == _staking, "caller is not staking");
        _;
    }

    constructor(address adminPanel) {
        _initiatePlatformAccessController(adminPanel);
        tgeStartDate = block.timestamp;
    }

    function getVestingCount() external view returns (uint256) {
        return _vestingCount;
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

    /**
     * @notice Get vesting pool properties list
     * vesting.isStakeSupport   Specifies whether unclaim funds can be used for staking
     * vesting.amountForUser   Total PROP amount which user can claim
     * vesting.tgeAmountForUser   PROP amount which user can claim immediately after the `startTime`
     * vesting.startTime   The moment after that users can start claim `tgeAmountForUser`
     * vesting.tickCount   The number of ticks that must pass to fully unlock funds
     * Each tick unlocks a proportional amount
     * vesting.tickDuration   Tick duration on seconds
     * vesting.unallocateAmount PROP that has not yet been assigned to any users
     * Grows when users are deleted and iquidity is increased by the admin
     * Falls when users are deleted and the liquidity is reduced by the admin
     */
    function vestingPropertiesList()
        external
        view
        returns (VestingProperties[] memory vestingList)
    {
        uint256 count = _vestingCount;

        vestingList = new VestingProperties[](count);

        while (0 < count) {
            --count;

            vestingList[count] = _vestingMap[count];
        }
    }

    /**
     * @notice Get properties list for the user
     * @param wallet User wallet
     * user.isActive   Indicates whether the user is on the whitelist or not
     * Admin can add or remove users.
     * user.spentAmount   Amount that was branded by the user or seized as staking fee
     * user.stakeAmount   Amount that was stake by the user
     */
    function userPropertiesList(address wallet)
        external
        view
        returns (UserProperties[] memory userList)
    {
        uint256 count = _vestingCount;

        userList = new UserProperties[](count);

        mapping(uint256 => UserProperties) storage map = _userMapping[wallet];
        while (0 < count) {
            --count;

            userList[count] = map[count];
        }
    }

    /**
     * @notice Get possible claim amount for user list for all vestings pools
     * @param wallet User wallet
     * @param timestampInSeconds Time at which they plan to make claim
     */
    function amountForClaimList(address wallet, uint256 timestampInSeconds)
        external
        view
        returns (uint256[] memory amountList)
    {
        uint256 count = _vestingCount;
        amountList = new uint256[](count);

        mapping(uint256 => UserProperties) storage map = _userMapping[wallet];
        while (0 < count) {
            --count;

            VestingProperties storage vesting = _vestingMap[count];
            UserProperties storage user = map[count];
            amountList[count] = _amountForClaim(
                vesting,
                user,
                timestampInSeconds
            );
        }
    }

    /**
     * @notice Get stake amount for user list for all vestings pools
     * @param wallet User wallet
     */
    function stakeAmountList(address wallet)
        external
        view
        returns (uint256[] memory amountList)
    {
        uint256 count = _vestingCount;

        amountList = new uint256[](count);

        mapping(uint256 => UserProperties) storage map = _userMapping[wallet];
        while (0 < count) {
            --count;

            UserProperties storage user = map[count];
            amountList[count] = user.stakeAmount;
        }
    }

    /**
     * @notice Only platform admin can do
     * If 0 < vesting.unallocateAmount amount will be transfer from sender wallet
     */
    function insertVestingList(
        VestingProperties[] calldata vestingList,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyPlatformAdmin {
        uint256 count = _vestingCount;

        require(
            count + vestingList.length <= MAX_VESTING_COUNT,
            "vesting count overflow"
        );

        require(0 < vestingList.length, "empty vesting list");

        uint256 liquidity;

        address admin = msgSender();

        uint256 index = vestingList.length;

        while (0 < index) {
            --index;

            liquidity += _setVesting(count + index, vestingList[index]);
        }

        increaseVestingCount(vestingList.length);

        IPlatformToken(_token).specialTransferFrom(
            admin,
            liquidity,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        if (liquidity > 0) {
            emit InsertVestingList(msgSender(), vestingList.length);
        }
    }

    /**
     * @notice This is a fix to increase vesting count
     * @param _count amount to invest vesting count by
     */

    function increaseVestingCount(uint256 _count) internal {
        _vestingCount = _vestingCount + _count;
    }

    /**
     * @notice Only platform admin can do
     * @param vestingId Target vesting pool id
     * @param amount Target additional liquidity amount
     * Amount will be transfer from sender wallet
     */
    function increaseLiquidity(
        uint256 vestingId,
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyPlatformAdmin existingVesting(vestingId) {
        require(0 < amount, "zero amount");

        VestingProperties storage vesting = _vestingMap[vestingId];

        vesting.unallocateAmount += amount;

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

        emit IncreaseLiquidity(admin, vestingId, amount);
    }

    /**
     * @notice Only platform admin can do
     * @param vestingId Target vesting pool id
     * @param amount Target remitional liquidity amount
     * Amount will be transfer to sender wallet
     */
    function decreaseLiqudity(uint256 vestingId, uint256 amount)
        external
        onlyPlatformAdmin
        existingVesting(vestingId)
    {
        require(0 < amount, "zero amount");

        VestingProperties storage vesting = _vestingMap[vestingId];

        uint256 oldUnallocate = vesting.unallocateAmount;
        require(amount <= oldUnallocate, "insufficient liquidity");

        vesting.unallocateAmount = oldUnallocate - amount;

        address admin = msgSender();
        IPlatformToken(_token).transfer(admin, amount);

        emit DecreaseLiquidity(admin, vestingId, amount);
    }

    function insertWalletListToVesting(
        uint256 vestingId,
        address[] calldata walletList
    ) external onlyPlatformAdmin existingVesting(vestingId) {
        require(0 < walletList.length, "empty wallet list");

        uint256 decreasion;

        VestingProperties storage vesting = _vestingMap[vestingId];
        uint256 amountForUser = vesting.amountForUser;

        uint256 index = walletList.length;
        while (0 < index) {
            --index;

            address wallet = walletList[index];
            UserProperties storage user = _userMapping[wallet][vestingId];

            require(!user.isActive, "wallet already insert");
            user.isActive = true;

            decreasion += amountForUser - user.spentAmount;
        }

        uint256 oldUnallocate = vesting.unallocateAmount;

        require(decreasion <= oldUnallocate, "insufficient liquidity");

        vesting.unallocateAmount = oldUnallocate - decreasion;

        emit InsertWalletListToVesting(msgSender(), vestingId, walletList);
    }

    function removeWalletListFromVesting(
        uint256 vestingId,
        address[] calldata walletList
    ) external onlyPlatformAdmin existingVesting(vestingId) {
        require(0 < walletList.length, "empty wallet list");

        uint256 increasing;

        VestingProperties storage vesting = _vestingMap[vestingId];
        uint256 amountForUser = vesting.amountForUser;

        uint256 index = walletList.length;
        while (0 < index) {
            --index;

            address wallet = walletList[index];
            UserProperties storage user = _userMapping[wallet][vestingId];

            require(user.isActive, "wallet already remove");
            user.isActive = false;

            increasing += amountForUser - user.spentAmount;
        }

        vesting.unallocateAmount += increasing;

        emit RemoveWalletListFromVesting(msgSender(), vestingId, walletList);
    }

    /**
     * @notice Claim possible for user amount from the pool
     * If possible amounts equal to zero will revert
     * @param vestingId Target vesting pool id
     * @param wallet User wallet
     */

    function claim(uint256 vestingId, address wallet) external {
        VestingProperties storage vesting = _vestingMap[vestingId];
        UserProperties storage user = _userMapping[wallet][vestingId];

        uint256 claimAmount = _amountForClaim(vesting, user, block.timestamp);
        require(0 < claimAmount, "no claim funds");

        user.spentAmount += claimAmount;

        IPlatformToken(_token).transfer(wallet, claimAmount);

        emit Claim(vestingId, wallet, claimAmount);
    }

    /**
     * @dev Only staking contract can do
     */

    function unstake(address wallet)
        external
        onlyStaking
        returns (uint256 totalAmount)
    {
        uint256 count = _vestingCount;

        mapping(uint256 => UserProperties) storage map = _userMapping[wallet];
        while (0 < count) {
            --count;

            UserProperties storage user = map[count];

            uint256 amount = user.stakeAmount;
            if (amount == 0) {
                continue;
            }

            user.stakeAmount = 0;
            totalAmount += amount;
        }

        require(0 < totalAmount, "PV: no contract changes");
    }

    function _share(
        uint256 amount,
        uint256 share,
        uint256 total
    ) private pure returns (uint256) {
        return (amount * share) / total;
    }

    function _amountForClaim(
        VestingProperties storage vesting,
        UserProperties storage user,
        uint256 nowTime
    ) private view returns (uint256) {
        uint256 startTime = vesting.startTime;
        if (nowTime < startTime) {
            return 0;
        }

        if (!user.isActive) {
            return 0;
        }

        uint256 tickCount = vesting.tickCount;
        uint256 tick = (nowTime - startTime) / vesting.tickDuration;

        uint256 amount = vesting.tgeAmountForUser;
        uint256 rest = vesting.amountForUser - amount;
        if (tick < tickCount) {
            uint256 share = _share(TOTAL_SHARE, tick, tickCount);
            amount += _share(rest, share, TOTAL_SHARE);
        } else {
            amount += rest;
        }

        uint256 sp = user.spentAmount;
        uint256 st = user.stakeAmount;
        if (amount <= sp + st) {
            return 0;
        }

        return amount - sp - st;
    }

    function _setVesting(uint256 vestingId, VestingProperties calldata setting)
        private
        returns (uint256 liquidity)
    {
        require(
            setting.tgeAmountForUser <= setting.amountForUser,
            "incorrect tge amount"
        );

        require(setting.startTime > block.timestamp, "incorrect vesting time");

        require(
            setting.startTime > block.timestamp - tgeStartDate,
            "incorrect vesting time"
        );

        if (setting.tgeAmountForUser < setting.amountForUser) {
            require(0 < setting.tickCount, "incorrect tick amount");
            require(0 < setting.tickDuration, "incorrect tick duration");
        }

        _vestingMap[vestingId] = setting;

        liquidity = setting.unallocateAmount;
    }

    /**
     * @notice
     * @param vestingId Target vesting pool id
     * @param wallet User wallet
     * @param amount amount to be vested
     * @param feeShare amount of unit share
     * @param totalShare total share
     */
    function _stake(
        uint256 vestingId,
        address wallet,
        uint256 amount,
        uint256 feeShare,
        uint256 totalShare
    ) external returns (uint256 fee) {
        VestingProperties storage vesting = _vestingMap[vestingId];
        require(vesting.isStakeSupport, "PV: stake is not support");

        UserProperties storage user = _userMapping[wallet][vestingId];
        require(user.isActive, "PV: user is not active");

        uint256 sp = user.spentAmount;
        uint256 st = user.stakeAmount;

        uint256 freeAmount = vesting.amountForUser - sp - st;

        require(amount <= freeAmount, "PV: insufficient funds");

        fee = _share(amount, feeShare, totalShare);

        if (0 < fee) {
            vesting.unallocateAmount += fee;
            user.spentAmount = sp + fee;
        }

        user.stakeAmount = st + amount - fee;
    }
}
