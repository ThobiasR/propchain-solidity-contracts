// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "../STTransferStorage/ISTTransferStorage/ISTTransferStorage.sol";
import "../KYCStorage/IKYCStorage/IKYCStorage.sol";
import "../access_controller/PlatformAccessController.sol";
import "../RoyaltyDistributor/IRoyaltyDistributor/IRoyaltyDistributor.sol";
import "./ISTTransferController/ISTTransferController.sol";

contract STTransferController is
    ISTTransferController,
    PlatformAccessController
{
    uint256 public freeLine;
    uint256 public starLine;
    uint256 public moviLine;
    uint256 public moguLine;
    uint256 public tycoLine;

    address private stFactory;

    address private stTransferStorage;
    address private kycStorage;
    address private royaltyDistributor;

    mapping(uint256 => mapping(uint256 => uint256)) private jurisdictionLimit;
    mapping(address => bool) private whiteListedMap;

    event UpdatedStFactoryAddress(address indexed factoryAddress);

    event UpdatedKycStorageAdress(address indexed kycAddress);

    event UpdatedStTransferStorageAddress(
        address indexed transferStorageAddress
    );

    event UpdatedRoyaltyDistributorAddress(
        address indexed royaltyDistributorAddress
    );

    modifier ristrictedAccess() {
        require(
            msg.sender == stFactory ||
                PlatformAdminPanel(_panel).isAdmin(msgSender()),
            "unauthorized caller"
        );
        _;
    }

    constructor(
        uint256 _free,
        uint256 _star,
        uint256 _movi,
        uint256 _mogu,
        uint256 _tyco,
        address adminPanel,
        address _transferStorage,
        address _kycStorage,
        address _royaltyDistributor
    ) {
        require(adminPanel != address(0), "address is zero address");
        require(_transferStorage != address(0), "address is zero address");
        require(_kycStorage != address(0), "address is zero address");
        require(_royaltyDistributor != address(0), "address is zero address");
        _initiatePlatformAccessController(adminPanel);
        freeLine = _free;
        starLine = _star;
        moviLine = _movi;
        moguLine = _mogu;
        tycoLine = _tyco;
        stTransferStorage = _transferStorage;
        kycStorage = _kycStorage;
        royaltyDistributor = _royaltyDistributor;
    }

    event NewJurisdictioLimit(
        uint256 token,
        uint256 jurisdiction,
        uint256 limit
    );

    function setStFactory(address _stFactory) external onlyPlatformAdmin {
        require(_stFactory != address(0), "address is zero address");
        stFactory = _stFactory;
        emit UpdatedStFactoryAddress(_stFactory);
    }

    function setKycStorage(address _kycStorage) external onlyPlatformAdmin {
        require(_kycStorage != address(0), "address is zero address");
        kycStorage = _kycStorage;
        emit UpdatedKycStorageAdress(_kycStorage);
    }

    function setStTransferStorage(address _stTransferStorage)
        external
        onlyPlatformAdmin
    {
        require(_stTransferStorage != address(0), "address is zero address");
        stTransferStorage = _stTransferStorage;
        emit UpdatedStTransferStorageAddress(_stTransferStorage);
    }

    function setRoyaltyDistributor(address _royaltyDistributor)
        external
        onlyPlatformAdmin
    {
        require(_royaltyDistributor != address(0), "address is zero address");
        royaltyDistributor = _royaltyDistributor;
        emit UpdatedRoyaltyDistributorAddress(_royaltyDistributor);
    }

    function updateTierLimit(
        uint256 _free,
        uint256 _star,
        uint256 _movi,
        uint256 _mogu,
        uint256 _tyco
    ) external onlyPlatformAdmin {
        require(
            _free > 0 && _star > 0 && _movi > 0 && _mogu > 0 && _tyco > 0,
            "under value"
        );

        freeLine = _free;
        starLine = _star;
        moviLine = _movi;
        moguLine = _mogu;
        tycoLine = _tyco;
    }

    /**
     * @dev add a jurisdiction limit
     * @param _jurisdictions jurisdiction identifier
     * @param _limits jurisdiction limit
     **/
    function addJurisdictionLimt(
        uint256 _token,
        uint256[] memory _jurisdictions,
        uint256[] memory _limits
    ) external virtual override ristrictedAccess {
        uint256 jurisdictionsIndex = _jurisdictions.length;
        uint256 limtsIndex = _limits.length;

        require(
            jurisdictionsIndex == limtsIndex,
            "unequal limts and jurisdictions"
        );

        while (0 < jurisdictionsIndex) {
            --jurisdictionsIndex;

            uint256 juri = _jurisdictions[jurisdictionsIndex];
            uint256 limit = _limits[jurisdictionsIndex];

            require(jurisdictionLimit[_token][juri] < limit, "cant reduce");

            jurisdictionLimit[_token][juri] = limit;

            emit NewJurisdictioLimit(_token, juri, limit);
        }
    }

    /**
     * @dev this helps to check that all trasnfer requirements pass
     * @param _user user address to recieve token
     * @param _from user address from which token is sent
     * @param _token token id to be sent
     * @param _amount amount at which token is exchanged for
     **/
    function makeTransfer(
        address _user,
        address _from,
        uint256 _token,
        uint256 _amount,
        uint256 _price
    ) external virtual override {
        require(whiteListedMap[msg.sender], "unauthorized caller");
        require(
            IKYCStorage(kycStorage).checkVerifiedUser(_user),
            "unverified user"
        );

        uint256 _toJurisdiction = verifyJurisdictionInvestment(
            _user,
            _token,
            _amount,
            _price
        );

        IRoyaltyDistributor(royaltyDistributor).handleMidMonthTransfer(
            _amount,
            _from,
            _user,
            _token
        );

        ISTTransferStorage(stTransferStorage).transfer(
            _user,
            _from,
            _token,
            _amount,
            _price,
            _toJurisdiction
        );
    }

    function verifyJurisdictionInvestment(
        address _user,
        uint256 _token,
        uint256 _amount,
        uint256 _price
    ) public view virtual override returns (uint256) {
        (, uint256 _toJurisdiction, UserTier _userTier) = IKYCStorage(
            kycStorage
        ).getUser(_user);

        uint256 tierCredit = getUserTierValue(_userTier);

        uint256 allowance = ISTTransferStorage(stTransferStorage)
            .getUserAllowance(_user, _token);

        uint256 totalJurisdictionInvestment = ISTTransferStorage(
            stTransferStorage
        ).getpropertyJurisdictionInvestment(_token, _toJurisdiction);

        require(
            totalJurisdictionInvestment <
                jurisdictionLimit[_token][_toJurisdiction],
            "reached jurisdiction limit"
        );

        require(
            allowance + (_amount * _price) < tierCredit,
            "reached tier limit"
        );

        return _toJurisdiction;
    }

    /**
     * @dev get value for user tier
     * @param tier user tier needed to get value
     **/
    function getUserTierValue(UserTier tier) internal view returns (uint256) {
        if (tier == UserTier.FREE) {
            return freeLine;
        }
        if (tier == UserTier.STAR) {
            return starLine;
        }
        if (tier == UserTier.MOVI) {
            return moviLine;
        }
        if (tier == UserTier.MOGU) {
            return moguLine;
        }
        if (tier == UserTier.TYCO) {
            return tycoLine;
        }

        return 0;
    }

    /**
     * @dev adds address of a newly craeted stToken contract
     * @param whiteListAddress array of users address to be inputed
     **/
    function setWhitelistedContracts(address whiteListAddress)
        external
        virtual
        override
        onlyPlatformAdmin
    {
        require(msg.sender == stFactory, "unauthorized caller");

        whiteListedMap[whiteListAddress] = true;
    }
}
