// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../access_controller/PlatformAccessController.sol";
import "../factory/IstFactory/ISTFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../KYCStorage/IKYCStorage/IKYCStorage.sol";
import "./IRoyaltyDistributor/IRoyaltyDistributor.sol";

contract RoyaltyDistributor is IRoyaltyDistributor, PlatformAccessController {
    mapping(uint256 => uint256) private maxPropertySupply;

    mapping(uint256 => mapping(uint256 => uint256)) private tokenBalance;

    mapping(uint256 => uint256) public tokenCurrentMonth;

    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        private holdersBalance;

    mapping(address => mapping(uint256 => uint256)) private lastClaimed;
    mapping(uint256 => uint256) private lastRentDistribution;

    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        private midMonthClaim;

    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        private midMonthClaimBalance;

    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        private midMonthSent;

    mapping(address => mapping(uint256 => mapping(uint256 => bool)))
        private midMonthSale;

    uint256 private claimFee;

    uint256 private adminBalance;

    address public token;
    address public factory;
    address public kycStorage;
    address public StTransferController;

    event DistributeRent(uint256 property, uint256 amount, uint256 month);

    event ClaimRent(uint256 property, uint256 amount, uint256 month);

    event BatchClaimRent(uint256[] property, uint256 amount, uint256[] month);

    event UpdatedTokenAddress(address indexed tokenAddress);

    event UpdatedFactoryAddress(address indexed factory);

    event UpdatedKycStorageAddress(address indexed kycStorage);

    event UpdatedSTTransferControllerAddress(
        address indexed StTransferController
    );

    event UpdatedClaimFee(uint256 claimFee);

    constructor(address adminPanel) {
        require(adminPanel != address(0), "address is zero address");
        _initiatePlatformAccessController(adminPanel);
    }

    function updateTokenAddress(address _token) external onlyPlatformAdmin {
        require(_token != address(0), "cant be zero address");
        token = _token;
        emit UpdatedTokenAddress(_token);
    }

    function updateFactoryAddress(address _factory) external onlyPlatformAdmin {
        require(_factory != address(0), "cant be zero address");
        factory = _factory;
        emit UpdatedFactoryAddress(_factory);
    }

    function updateKycStorageAddress(address _kycStorage)
        external
        onlyPlatformAdmin
    {
        require(_kycStorage != address(0), "cant be zero address");
        kycStorage = _kycStorage;
        emit UpdatedKycStorageAddress(_kycStorage);
    }

    function updateSTTransferControllerAddress(address _StTransferController)
        external
        onlyPlatformAdmin
    {
        require(_StTransferController != address(0), "cant be zero address");
        StTransferController = _StTransferController;
        emit UpdatedSTTransferControllerAddress(_StTransferController);
    }

    function updateClaimFee(uint256 _fee) external onlyPlatformAdmin {
        claimFee = _fee;
        emit UpdatedClaimFee(_fee);
    }

    function addMaxPropertySupply(uint256 _property, uint256 _maxSupply)
        external
        virtual
        override
    {
        require(msg.sender == factory, "caller is unauthorized");
        maxPropertySupply[_property] = _maxSupply;
    }

    function getCurrentMonth(uint256 _property) public view returns (uint256) {
        return tokenCurrentMonth[_property];
    }

    function increaseCurrentMonth(uint256 _property) internal {
        uint256 temp = getCurrentMonth(_property);

        tokenCurrentMonth[_property] = temp + 1;
    }

    /**
     * @dev entity who owns property or admin can distribute rent
     * only admin or entity
     * @param _property number of property you'd like to distribute rent for
     * @param _amount amount to be distributed
     */
    function distributeRent(uint256 _property, uint256 _amount) external {
        require(
            block.timestamp >= lastRentDistribution[_property] + 30 days,
            "last distribution less than 30 days "
        );

        address sender = msg.sender;

        address entityAddress = ISTFactory(factory).checkStEntityToken(
            _property
        );

        require(
            sender == entityAddress ||
                PlatformAdminPanel(_panel).isAdmin(msgSender()),
            "unauthorized caller"
        );

        bool state = IERC20(token).transferFrom(sender, address(this), _amount);

        require(state, "failed transfer");

        uint256 month = getCurrentMonth(_property) + 1;

        uint256 temp = maxPropertySupply[_property];

        uint256 amount = _amount / temp;

        increaseCurrentMonth(_property);

        lastRentDistribution[_property] = block.timestamp;

        tokenBalance[_property][month] = amount;

        emit DistributeRent(_property, _amount, month);
    }

    /**
     * @dev holder use this to make single claim at once
     * @param _property number of all property to make claim for
     * @param _month month you'd like to make claim for
     */
    function claimRent(uint256 _property, uint256 _month) external {
        address sender = msg.sender;

        uint256 limit = claim(_property, sender, _month);

        bool state = IERC20(token).transfer(sender, limit);

        require(state, "failed transfer");

        emit ClaimRent(_property, limit, _month);
    }

    /**
     * @dev holder use this to make multiple claims at once
     * @param _properties an array of number of all properties
     * @param _months an array months you'd like to make claim for
     */
    function batchClaimRent(
        uint256[] memory _properties,
        uint256[] memory _months
    ) external {
        address sender = msg.sender;

        require(_properties.length == _months.length, "unequal length");

        uint256 index = _properties.length;

        uint256 limit;

        while (0 < index) {
            --index;

            uint256 temp = claim(_properties[index], sender, _months[index]);

            limit = limit + temp;
        }

        bool state = IERC20(token).transfer(sender, limit);

        require(state, "failed transfer");

        emit BatchClaimRent(_properties, limit, _months);
    }

    function getCycle(
        address _user,
        UserTier tier,
        uint256 _property
    ) public view returns (bool) {
        uint256 temp = lastClaimed[_user][_property];
        uint256 time;

        {
            if (tier == UserTier.FREE || tier == UserTier.STAR) {
                time = temp + 30 days;
            }
            if (tier == UserTier.MOVI) {
                time = temp + 14 days;
            }
            if (tier == UserTier.MOGU) {
                time = temp + 7 days;
            }
            if (tier == UserTier.TYCO) {
                time = temp + 24 hours;
            }

            if (block.timestamp < time) {
                return false;
            }
        }

        return true;
    }

    /**
     * @dev this is an internal function that helps to return a balance that can be claimed by a wallet
     * in a specific month on a specific
     * @param _property property number
     * @param sender address of user to claim for
     * @param _month month to be claimed for
     */
    function claim(
        uint256 _property,
        address sender,
        uint256 _month
    ) internal returns (uint256) {
        uint256 tempMonth = getCurrentMonth(_property);

        require(_month > tempMonth, "invalid month");

        address entityAddress = ISTFactory(factory).checkStEntityToken(
            _property
        );

        (, , , address tokenAddress) = ISTFactory(factory).tokenPropertiesOf(
            entityAddress
        );

        (, , UserTier tier) = IKYCStorage(kycStorage).getUser(sender);

        uint256 temp = IERC1155(tokenAddress).balanceOf(sender, _property);

        uint256 balance = tokenBalance[_property][_month];

        uint256 limit = holdersBalance[sender][_property][_month];

        uint256 tempExtra;

        uint256 tempLimit;

        require(limit < balance * temp, "maxed out");

        require(getCycle(sender, tier, _property), "claim limit maxed");

        if (getMidMonthTx(_property, _month)) {
            tempLimit = midMonthSent[sender][_property][_month];

            if (tempLimit >= temp) {
                tempExtra = tempLimit - temp;
            }

            if (temp >= tempLimit) {
                tempExtra = temp - tempLimit;
            }
        }

        holdersBalance[sender][_property][_month] = temp * balance;

        tempLimit = (tempLimit * balance) / 2;

        uint256 payment = ((tempExtra * balance) + tempLimit) - limit;

        require(payment > 0, "invalid balance");

        lastClaimed[sender][_property] = block.timestamp;

        return payment;
    }

    /**
     * @dev this is a function that helps to return a balance that can be claimed by a wallet
     * that is eligible for half of the rent payed in a specific month is they sold during that month
     * @param _property property number
     * @param _month month to be claimed for
     */
    function claimAfterMidMonthTx(uint256 _property, uint256 _month) external {
        address sender = msg.sender;

        uint256 temp = midMonthClaim[sender][_property][_month];

        require(temp > 0, "no transfers made");

        uint256 tempMonth = getCurrentMonth(_property);

        require(_month > tempMonth, "invalid month");

        (, , UserTier tier) = IKYCStorage(kycStorage).getUser(sender);

        uint256 limit = midMonthClaimBalance[sender][_property][_month];

        uint256 balance = tokenBalance[_property][_month];

        uint256 tempBalance = balance * temp;

        require(limit < tempBalance, "maxed out");

        require(getCycle(sender, tier, _property), "claim limit maxed");

        midMonthClaimBalance[sender][_property][_month] = tempBalance;

        tempBalance = (tempBalance - limit) / 2;

        require(tempBalance > 0, "invalid balance");

        lastClaimed[sender][_property] = block.timestamp;

        bool state = IERC20(token).transfer(sender, tempBalance);

        require(state, "failed transfer");
    }

    /**
     * @dev force claim for a user only admin
     * only admin
     * @param _property property number
     * @param _user address of user to force claim for
     */
    function forceClaim(uint256 _property, address _user)
        external
        onlyPlatformAdmin
    {
        uint256 tempMonth = getCurrentMonth(_property);

        tempMonth = tempMonth - 1;

        require(tempMonth > 0, "invalid month");

        uint256 limit;

        while (1 < tempMonth) {
            uint256 tempLimit = claim(_property, _user, tempMonth);

            limit = limit + tempLimit;

            --tempMonth;
        }

        require(limit > claimFee, "invalid number");

        limit = limit - claimFee;

        adminBalance = adminBalance + claimFee;

        bool state = IERC20(token).transfer(_user, limit);

        require(state, "failed transfer");
    }

    /**
     * @dev withdraw fees accumulated for force transfers
     */
    function withdraw() external onlyPlatformAdmin {
        address sender = msg.sender;

        uint256 temp = adminBalance;

        adminBalance = 0;

        bool state = IERC20(token).transfer(sender, temp);

        require(state, "failed transfer");
    }

    /**
     * @dev this function helps to update the data in this contract when a token is sent
     * @param _amount amount of property exchnaged
     * @param holder address of user transferrign property
     * @param _to address of user recieving property
     * @param _property property id
     */
    function handleMidMonthTransfer(
        uint256 _amount,
        address holder,
        address _to,
        uint256 _property
    ) external virtual override {
        require(msg.sender == StTransferController, "caller is unauthorized");
        uint256 tempTime = getCurrentMonth(_property);

        handleMidMonthTx(_amount, holder, _to, _property, tempTime);

        while (1 < tempTime) {
            uint256 tempAmount = holdersBalance[holder][_property][tempTime];

            holdersBalance[_to][_property][tempTime] =
                holdersBalance[_to][_property][tempTime] +
                tempAmount;

            holdersBalance[holder][_property][tempTime] =
                holdersBalance[holder][_property][tempTime] -
                tempAmount;

            tempTime = tempTime - 1;
        }
    }

    function handleMidMonthTx(
        uint256 _amount,
        address _to,
        address _from,
        uint256 _property,
        uint256 _month
    ) internal {
        midMonthClaim[_from][_property][_month] =
            midMonthClaim[_from][_property][_month] +
            _amount;

        midMonthSent[_to][_property][_month] =
            midMonthSent[_to][_property][_month] +
            _amount;

        midMonthSale[_to][_property][_month] = true;
    }

    function getMidMonthTx(uint256 _property, uint256 _month)
        internal
        view
        returns (bool)
    {
        return midMonthSale[msg.sender][_property][_month];
    }
}
