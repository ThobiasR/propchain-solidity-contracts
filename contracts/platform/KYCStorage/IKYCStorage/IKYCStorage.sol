// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

enum UserTier {
    FREE,
    STAR,
    MOVI,
    MOGU,
    TYCO
}

interface IKYCStorage {
    /**
     * @dev check if a user is verified
     * @param _user address of user
     **/
    function checkVerifiedUser(address _user) external view returns (bool);

    /**
     * @dev adds addresses that are whitelisted for a specific token
     * @param whiteList array of users address to be inputed
     * @param _token token to whitelist addresses for
     **/
    function insertWhiteList(address[] calldata whiteList, uint256 _token)
        external;

    /**
     * @dev remove addresses that had been whitelisted for a specific token
     * @param whiteList array of users address to be removed
     * @param _token token to remove whitelist addresses for
     **/
    function removeWhiteList(address[] calldata whiteList, uint256 _token)
        external;

    /**
     * @dev retrives user data from kyc storage
     * @param _user address of user
     **/
    function getUser(address _user)
        external
        view
        returns (
            address userAddress,
            uint256 _jurisdiction,
            UserTier _userTier
        );

    function getWhiteListedAddress(address _sender, uint256 _token)
        external
        view
        returns (bool);
}
