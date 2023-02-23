// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "../access_controller/PlatformAccessController.sol";
import "../KYCStorage/IKYCStorage/IKYCStorage.sol";
import "./ISTTransferStorage/ISTTransferStorage.sol";

contract STTransferStorage is ISTTransferStorage, PlatformAccessController {
    address private stEscrow;
    address private kycStorage;
    address private sTTransferController;

    mapping(address => bool) private isOnStorage;

    mapping(uint256 => uint256) private propertyInvestment;

    mapping(address => mapping(uint256 => uint256))
        private userPropertyAllowance;

    mapping(uint256 => mapping(uint256 => uint256))
        private propertyJurisdictionInvestment;

    event NewExchange(
        address indexed to,
        uint256 toJurisdiction,
        address indexed from,
        uint256 fromJurisdiction,
        uint256 amount
    );

    event UpdatedKycStorageAddress(address indexed kycAddress);

    event UpdatedEscrowAddress(address indexed escrowAddress);

    event UpdatedStTransferControllerAddress(
        address indexed sTTransferController
    );

    modifier onlySTTransferController() {
        require(msg.sender == sTTransferController, "unauthorized caller");
        _;
    }

    constructor(address adminPanel) {
        _initiatePlatformAccessController(adminPanel);
    }

    function setStEscrow(address _stEscrow) external onlyPlatformAdmin {
        require(_stEscrow != address(0), "address is zero address");
        stEscrow = _stEscrow;
        emit UpdatedEscrowAddress(_stEscrow);
    }

    function setStKycStorage(address _kycStorage) external onlyPlatformAdmin {
        require(_kycStorage != address(0), "address is zero address");
        kycStorage = _kycStorage;
        emit UpdatedKycStorageAddress(_kycStorage);
    }

    function setSTTransferController(address _sTTransferController)
        external
        onlyPlatformAdmin
    {
        require(_sTTransferController != address(0), "address is zero address");
        sTTransferController = _sTTransferController;
        emit UpdatedStTransferControllerAddress(_sTTransferController);
    }

    /**
     * @dev this function updates variables according to transfer
     * @dev this function checks if transfer is from escrow contract || token contract ( can be reviewed )
     * @param _to address of user
     * @param _from address of sender
     * @param _token token to be transferred
     * @param _amount price for token
     * @param _toJurisdiction jurisdiction that receives token
     **/
    function transfer(
        address _to,
        address _from,
        uint256 _token,
        uint256 _amount,
        uint256 _price,
        uint256 _toJurisdiction
    ) external virtual override onlySTTransferController {
        (, uint256 _fromJurisdiction, ) = IKYCStorage(kycStorage).getUser(
            _from
        );

        uint256 temp = _amount * _price;

        if (msg.sender != stEscrow) {
            propertyJurisdictionInvestment[_token][_fromJurisdiction] -= temp;

            userPropertyAllowance[_from][_token] -= temp;
        }

        propertyJurisdictionInvestment[_token][_toJurisdiction] += temp;

        userPropertyAllowance[_to][_token] += temp;

        if (!isOnStorage[_to]) isOnStorage[_to] = true;

        emit NewExchange(
            _to,
            _toJurisdiction,
            _from,
            _fromJurisdiction,
            _amount
        );
    }

    /**
     * @dev this function gets the current allowance of jurisdiction on a property
     * @param _token token id to map to
     * @param _jurisdiction
     **/
    function getpropertyJurisdictionInvestment(
        uint256 _token,
        uint256 _jurisdiction
    ) external view virtual override returns (uint256) {
        return propertyJurisdictionInvestment[_token][_jurisdiction];
    }

    /**
     * @dev this function gets the current allowance of user
     * @param _user address of user
     * @param _token token id to map to
     **/
    function getUserAllowance(address _user, uint256 _token)
        external
        view
        virtual
        override
        returns (uint256)
    {
        bool exist = isOnStorage[_user];

        if (exist == false) return 0;

        return userPropertyAllowance[_user][_token];
    }
}
