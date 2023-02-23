// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "../access_controller/PlatformAccessController.sol";
import "../KYCStorage/IKYCStorage/IKYCStorage.sol";
import "../STTransferController/ISTTransferController/ISTTransferController.sol";
import "./Isttoken/ISTToken.sol";

contract STToken is ERC1155, ISTToken, PlatformAccessController {
    address public immutable factory;
    address public immutable owner;
    string public name;

    address private immutable stEscrow;
    address private immutable isPanel;
    address private immutable kycStorage;
    address private immutable transferController;

    mapping(uint256 => StpropertyData) public stTokenIdDataMap;
    mapping(uint256 => uint256) public mintCountMap;
    mapping(uint256 => bool) public isExistMap;

    struct StpropertyData {
        string propertyName;
        uint256 tokenId;
        uint256 maxSupply;
        uint256 softCap;
        uint256 jurisdiction;
        uint256 price;
    }

    event NewTokenCreated(
        string propertyName,
        uint256 tokenId,
        uint256 maxSupply,
        uint256 price
    );

    event MintedToken(address indexed to, uint256 tokenId, uint256 amouunt);

    modifier ristrictedAccess() {
        require(
            msg.sender == owner ||
                PlatformAdminPanel(isPanel).isAdmin(msgSender()),
            "unauthorized caller"
        );
        _;
    }

    constructor(
        address _owner,
        string memory _name,
        address adminPanel,
        address _factory,
        address _kycStorage,
        address _stEscrow,
        address _transferController
    ) ERC1155("") {
        require(_owner != address(0), "address is zero address");
        require(adminPanel != address(0), "address is zero address");
        require(_factory != address(0), "address is zero address");
        require(_kycStorage != address(0), "address is zero address");
        require(_stEscrow != address(0), "address is zero address");
        require(_transferController != address(0), "address is zero address");
        factory = _factory;
        owner = _owner;
        name = _name;
        isPanel = adminPanel;
        _initiatePlatformAccessController(adminPanel);
        kycStorage = _kycStorage;
        stEscrow = _stEscrow;
        transferController = _transferController;
    }

    function createToken(
        uint256 _id,
        uint256 _supply,
        string calldata _name,
        uint256 _softCap,
        uint256 _jurisdiction,
        uint256 _price
    ) external virtual override {
        require(msg.sender == factory, "is not factory");
        StpropertyData memory _propertyData;
        _propertyData.propertyName = _name;
        _propertyData.tokenId = _id;
        _propertyData.maxSupply = _supply;
        _propertyData.softCap = _softCap;
        _propertyData.jurisdiction = _jurisdiction;
        _propertyData.price = _price;
        stTokenIdDataMap[_id] = _propertyData;

        isExistMap[_id] = true;
        emit NewTokenCreated(_name, _id, _supply, _price);
    }

    function getSTokenIdDataMap(uint256 id)
        external
        view
        virtual
        override
        returns (
            uint256 _id,
            uint256 _supply,
            string memory _name
        )
    {
        StpropertyData memory _data = stTokenIdDataMap[id];
        return (_data.tokenId, _data.maxSupply, _data.propertyName);
    }

    function mintToken(
        address _to,
        uint256 _stTokedId,
        uint256 _amount
    ) external virtual override {
        require(msg.sender == stEscrow, "no authority to mint");

        require(isExistMap[_stTokedId], "no token id");
        uint256 _temp = mintCountMap[_stTokedId] + _amount;
        require(
            _temp <= stTokenIdDataMap[_stTokedId].maxSupply,
            "passed maximun mint"
        );

        mintCountMap[_stTokedId] = _temp;

        _mint(_to, _stTokedId, _amount, "");
        emit MintedToken(_to, _stTokedId, _amount);
    }

    function getStToken() external view returns (address) {
        return address(this);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner nor approved"
        );

        StpropertyData memory tokenData = stTokenIdDataMap[id];

        ISTTransferController(transferController).makeTransfer(
            to,
            from,
            id,
            amount,
            tokenData.price
        );

        _safeTransferFrom(from, to, id, amount, data);
    }

    function aunthenticateEscrow(uint256 _token, address _sender)
        external
        view
        virtual
        override
        returns (bool)
    {
        require(
            _sender == owner ||
                PlatformAdminPanel(isPanel).isAdmin(msgSender()),
            "unauthorized caller"
        );
        bool state = isExistMap[_token];
        require(state, "invalid token");
        return true;
    }

    function getStTokenPrice(uint256 _token)
        external
        view
        virtual
        override
        returns (uint256)
    {
        StpropertyData memory tokenData = stTokenIdDataMap[_token];
        return tokenData.price;
    }
}
