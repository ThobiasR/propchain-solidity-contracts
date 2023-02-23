// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IPlatformVesting {
    /**
     * @dev Only staking contract can do
     */

    function unstake(address wallet) external returns (uint256 totalAmount);

    /**
     * @notice Get stake amount for user list for all vestings pools
     * @param wallet User wallet
     */
    function stakeAmountList(address wallet)
        external
        view
        returns (uint256[] memory amountList);

    function _stake(
        uint256 vestingId,
        address wallet,
        uint256 amount,
        uint256 feeShare,
        uint256 totalShare
    ) external returns (uint256 fee);

    function getVestingCount() external returns (uint256);
}
