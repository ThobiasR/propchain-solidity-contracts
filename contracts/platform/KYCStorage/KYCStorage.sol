// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../access_controller/PlatformAccessController.sol";
import "./IKYCStorage/IKYCStorage.sol";
import "contracts/platform/factory/IstFactory/ISTFactory.sol";

contract KYCStorage is IKYCStorage, PlatformAccessController {
    address private stFactory;

    struct UserProperties {
        address user;
        uint256 jurisdiction;
        UserTier userTier;
    }

    mapping(address => bool) public isVerifiedMap;

    mapping(address => UserProperties) public verifiedUser;

    mapping(address => mapping(uint256 => bool)) private userWhitelistedTokens;

    mapping(address => bool) private whitelistedContracts;

    event VerifiedUser(
        address indexed user,
        uint256 jurisdiction,
        UserTier _tier
    );

    event InsertWhiteList(address[] whitelist, uint256 token);

    event RemoveWhiteList(address[] whitelist, uint256 token);

    event InsertWhiteListContracts(address[] contracts);

    event RemoveWhiteListContracts(address[] contracts);

    event UpdatedStFactoryAddress(address indexed stFactory);

    constructor(address adminPanel, address _stFactory) {
        require(_stFactory != address(0), "address is zero address");
        _initiatePlatformAccessController(adminPanel);
        stFactory = _stFactory;
    }

    function setStFactory(address _stFactory) external onlyPlatformAdmin {
        require(_stFactory != address(0), "address is zero address");
        stFactory = _stFactory;
        emit UpdatedStFactoryAddress(_stFactory);
    }

    /**
     * @dev adds verified users to kyc storage
     * @param _user address of new verified user
     * @param _jurisdiction jurisdiction of new verified user
     * @param _tier tier of new verified user
     **/
    function verifyUser(
        address _user,
        uint256 _jurisdiction,
        UserTier _tier
    ) external onlyPlatformAdmin {
        isVerifiedMap[_user] = true;

        UserProperties memory newUser;

        newUser.user = _user;
        newUser.jurisdiction = _jurisdiction;
        newUser.userTier = _tier;

        verifiedUser[_user] = newUser;

        emit VerifiedUser(_user, _jurisdiction, _tier);
    }

    /**
     * @dev check if a user is verified
     * @param _user address of user
     **/
    function checkVerifiedUser(address _user)
        public
        view
        virtual
        override
        returns (bool)
    {
        return isVerifiedMap[_user];
    }

    /**
     * @dev adds addresses that are whitelisted for a specific token
     * @param whiteList array of users address to be inputed
     * @param _token token to whitelist addresses for
     **/
    function insertWhiteList(address[] calldata whiteList, uint256 _token)
        external
    {
        require(
            msg.sender == ISTFactory(stFactory).checkStEntityToken(_token) ||
                PlatformAdminPanel(_panel).isAdmin(msgSender()),
            "unauthorized caller"
        );
        require(0 < whiteList.length, "empty users list");

        uint256 index = whiteList.length;

        while (0 < index) {
            --index;
            address temp = whiteList[index];

            require(checkVerifiedUser(temp), " user does not exist ");
            userWhitelistedTokens[temp][_token] = true;
        }

        emit InsertWhiteList(whiteList, _token);
    }

    /**
     * @dev remove addresses that had been whitelisted for a specific token
     * @param whiteList array of users address to be removed
     * @param _token token to remove whitelist addresses for
     **/
    function removeWhiteList(address[] calldata whiteList, uint256 _token)
        external
    {
        require(
            msg.sender == ISTFactory(stFactory).checkStEntityToken(_token) ||
                PlatformAdminPanel(_panel).isAdmin(msgSender()),
            "unauthorized caller"
        );
        require(0 < whiteList.length, "empty users list");

        uint256 index = whiteList.length;

        while (0 < index) {
            --index;

            address temp = whiteList[index];

            require(checkVerifiedUser(temp), " user does not exist ");

            userWhitelistedTokens[temp][_token] = false;
        }

        emit RemoveWhiteList(whiteList, _token);
    }

    /**
     * @dev adds addresses from the propchain contracts to be whitelisted
     * @param whiteList array of users address to be inputed
     **/
    function insertWhiteListContracts(address[] calldata whiteList)
        external
        onlyPlatformAdmin
    {
        require(0 < whiteList.length, "empty contract list");

        uint256 index = whiteList.length;

        while (0 < index) {
            --index;
            address temp = whiteList[index];

            whitelistedContracts[temp] = true;
        }

        emit InsertWhiteListContracts(whiteList);
    }

    /**
     * @dev removes propchain contracts addresses that hadd been whitelisted
     * @param whiteList array of users address to be removed
     **/
    function removeWhiteListContracts(address[] calldata whiteList)
        external
        onlyPlatformAdmin
    {
        require(0 < whiteList.length, "empty contract list");

        uint256 index = whiteList.length;

        while (0 < index) {
            --index;
            address temp = whiteList[index];

            whitelistedContracts[temp] = false;
        }

        emit RemoveWhiteListContracts(whiteList);
    }

    /**
     * @dev retrives user data from kyc storage
     * @param _user address of user
     **/
    function getUser(address _user)
        external
        view
        virtual
        override
        returns (
            address userAddress,
            uint256 _jurisdiction,
            UserTier _userTier
        )
    {
        require(whitelistedContracts[msg.sender], "unauthorized caller");
        require(checkVerifiedUser(_user), "unverified user");
        UserProperties memory user = verifiedUser[_user];
        return (user.user, user.jurisdiction, user.userTier);
    }

    function getWhiteListedAddress(address _sender, uint256 _token)
        external
        view
        virtual
        override
        returns (bool)
    {
        return userWhitelistedTokens[_sender][_token];
    }
}
