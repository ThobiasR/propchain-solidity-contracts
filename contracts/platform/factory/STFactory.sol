// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "../sttoken/STToken.sol";
import "../access_controller/PlatformAccessController.sol";
import "../STTransferController/ISTTransferController/ISTTransferController.sol";
import "../RoyaltyDistributor/IRoyaltyDistributor/IRoyaltyDistributor.sol";
import "../STEscrow/ISTEscrow/ISTEscrow.sol";
import "./IstFactory/ISTFactory.sol";

contract STFactory is ISTFactory, PlatformAccessController {
    uint256 public entityCount = 0;

    uint256 public stTokenCount = 0;

    address private stTransferController;
    address private kycStorage;
    address private royaltyDistributor;
    address private stEscrow;

    struct EntityProperties {
        address companyAddress;
        uint256 companyId;
        string companyName;
        address stToken;
    }

    mapping(address => bool) private registeredEntity;
    mapping(address => EntityProperties) private entityPropertiesMap;
    mapping(uint256 => address) private stEntityToken;

    event Registered(
        address indexed companyAddress,
        uint256 companyId,
        string companyName,
        address indexed stToken
    );

    event NewStTokenIssued(
        string propertyName,
        uint256 tokenId,
        uint256 maxSupply,
        uint256 softCap,
        uint256 price
    );

    event UpdatedStTransferControllerAddress(
        address indexed stTransferController
    );

    event UpdatedKycStorageAddress(address indexed kycAddress);

    event UpdatedRoyaltyDistributorAddress(address indexed royaltyDistributor);

    event UpdatedEscrowAddress(address indexed escrow);

    constructor(address adminPanel) {
        require(adminPanel != address(0), "cant be zero address");

        _initiatePlatformAccessController(adminPanel);
    }

    function setStTransferController(address _stTransferController)
        external
        onlyPlatformAdmin
    {
        require(_stTransferController != address(0), "cant be zero address");
        stTransferController = _stTransferController;
        emit UpdatedStTransferControllerAddress(_stTransferController);
    }

    function setKycStorage(address _kycStorage) external onlyPlatformAdmin {
        require(_kycStorage != address(0), "cant be zero address");
        kycStorage = _kycStorage;
        emit UpdatedKycStorageAddress(_kycStorage);
    }

    function setRoyaltyDistributorAddress(address _royalty)
        external
        onlyPlatformAdmin
    {
        require(_royalty != address(0), "cant be zero address");
        royaltyDistributor = _royalty;
        emit UpdatedRoyaltyDistributorAddress(_royalty);
    }

    function setEscrowAddress(address _stEscrow) external onlyPlatformAdmin {
        require(_stEscrow != address(0), "cant be zero address");
        stEscrow = _stEscrow;
        emit UpdatedEscrowAddress(_stEscrow);
    }

    function checkEntity(address _companyAddress) internal view returns (bool) {
        return registeredEntity[_companyAddress];
    }

    /**
     * @dev Return enity properties
     * @param companyAddress The address of wallet that created token
     **/

    function tokenPropertiesOf(address _companyAddress)
        external
        view
        virtual
        override
        returns (
            address companyAddress,
            uint256 companyId,
            string memory companyName,
            address stToken
        )
    {
        EntityProperties memory _entity = entityPropertiesMap[_companyAddress];
        return (
            _entity.companyAddress,
            _entity.companyId,
            _entity.companyName,
            _entity.stToken
        );
    }

    /**
     * @dev this helps an enitity register
     * the setWhitelistedContracts on the ISTTransferController interface helps us add this new stToken address in the STTransferController
     * contract where we use it to restict access, each new stToken contract will have a unique address we need to account for that
     * @dev the wallet that registers an entity is how we indentify an entity
     * @param _companyName The address of wallet that created token
     **/

    function registerEntity(
        address _companyAddress,
        string calldata _companyName,
        address _transferController
    ) external onlyPlatformAdmin {
        require(!checkEntity(_companyAddress), "entity already registered");
        STToken _entityToken = new STToken(
            _companyAddress,
            _companyName,
            _panel,
            address(this),
            kycStorage,
            stEscrow,
            _transferController
        );

        address _entityTokenAddress = _entityToken.getStToken();

        ISTTransferController(stTransferController).setWhitelistedContracts(
            _entityTokenAddress
        );

        registeredEntity[_companyAddress] = true;

        uint256 _temp = entityCount + 1;

        EntityProperties memory _entity;

        _entity.companyAddress = _companyAddress;
        _entity.companyId = _temp;
        _entity.companyName = _companyName;
        _entity.stToken = _entityTokenAddress;

        entityPropertiesMap[_companyAddress] = _entity;

        entityCount++;

        emit Registered(
            _companyAddress,
            _temp,
            _companyName,
            _entityTokenAddress
        );
    }

    /**
     * @dev this is how an entity issues a new property
     * @param _name This is the name of the new property created
     * @param _maxSupply This is the maximum amount of token supply
     **/

    function newProperty(
        address _companyAddress,
        string memory _name,
        uint256 _maxSupply,
        uint256 _softCap,
        uint256 _jurisdiction,
        uint256 _price,
        uint256[] memory _jurisdictions,
        uint256[] memory _limts
    ) external {
        EntityProperties memory _entity = entityPropertiesMap[_companyAddress];
        require(
            msg.sender == _entity.companyAddress ||
                PlatformAdminPanel(_panel).isAdmin(msgSender()),
            "cannot create new token"
        );

        require(checkEntity(_companyAddress), "entity isn't registered");
        uint256 _temp = stTokenCount + 1;

        ISTToken(_entity.stToken).createToken(
            _temp,
            _maxSupply,
            _name,
            _softCap,
            _jurisdiction,
            _price
        );

        ISTTransferController(stTransferController).addJurisdictionLimt(
            _temp,
            _jurisdictions,
            _limts
        );

        stEntityToken[_temp] = _companyAddress;

        IRoyaltyDistributor(royaltyDistributor).addMaxPropertySupply(
            _temp,
            _maxSupply
        );

        stTokenCount++;

        emit NewStTokenIssued(_name, _temp, _maxSupply, _softCap, _price);
    }

    function checkTokenData(uint256 tid)
        external
        view
        returns (
            uint256 _id,
            uint256 _supply,
            string memory _name
        )
    {
        EntityProperties memory _entity = entityPropertiesMap[msg.sender];

        (uint256 id, uint256 supply, string memory name) = ISTToken(
            _entity.stToken
        ).getSTokenIdDataMap(tid);

        return (id, supply, name);
    }

    function checkStEntityToken(uint256 _token)
        external
        view
        virtual
        override
        returns (address)
    {
        return stEntityToken[_token];
    }

    function startEscrow(
        uint256 stTokenId,
        uint256 startTime,
        uint256 endTime,
        uint256 stAmountForPrice,
        uint256 usdAmountForPrice,
        uint256 softCapInUsd
    ) external {
        address sender = msg.sender;

        EntityProperties memory entity = entityPropertiesMap[sender];

        bool state = ISTToken(entity.stToken).aunthenticateEscrow(
            stTokenId,
            sender
        );

        require(state, "unauthorized caller");

        ISTEscrow(stEscrow).startEscrow(
            stTokenId,
            startTime,
            endTime,
            stAmountForPrice,
            usdAmountForPrice,
            softCapInUsd
        );
    }

    function cancelEscrow(uint256 stTokenId) external {
        address sender = msg.sender;

        EntityProperties memory entity = entityPropertiesMap[sender];

        bool state = ISTToken(entity.stToken).aunthenticateEscrow(
            stTokenId,
            sender
        );

        require(state, "unauthorized caller");

        ISTEscrow(stEscrow).cancelEscrow(stTokenId);
    }
}
