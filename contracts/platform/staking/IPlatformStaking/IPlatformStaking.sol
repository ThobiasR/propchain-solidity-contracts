// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

enum UserTier {
    FREE,
    STAR,
    MOVI,
    MOGU,
    TYCO
}

interface IPlatformStaking {
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
        returns (UserTier tier, bool isTierTurnOn);
}
