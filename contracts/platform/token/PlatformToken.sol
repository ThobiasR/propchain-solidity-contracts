// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../access_controller/PlatformAccessController.sol";
import "../KYCStorage/IKYCStorage/IKYCStorage.sol";
import "./price_provider/IPlatformTokenPriceProvider.sol";
import "./EIP3009/EIP3009.sol";

/**
 * @notice ERC20 token with some extra functionality
 * By default, there are restrictions on transfers to contracts not in whitelist
 * Method for transferring without approval, you can see the contracts that use it
 */
contract PlatformToken is ERC20, PlatformAccessController, EIP3009 {
    event InsertWalletListToAccessWhitelist(
        address indexed admin,
        address[] walletList
    );

    event RemoveWalletListFromAccessWhitelist(
        address indexed admin,
        address[] walletList
    );

    /**
     * @notice Emit during turn off access confines
     * @param admin Platform admin which do this action
     */
    event TurnOffAccessConfines(address indexed admin);

    address private _vesting;
    address private _staking;
    address private _cashback;

    address private _kycstorage;

    bool public _isAccessConfinesTurnOff = true;

    mapping(address => bool) public _accessWhitelistMap;

    modifier accessConfinesTurnOn() {
        require(_isAccessConfinesTurnOff, "access confines turn on");
        _;
    }

    /**
     * @param adminPanel platform admin panel address
     */
    constructor(
        address adminPanel,
        address recipient,
        uint256 supply
    ) ERC20("Propchain Token", "PROP") {
        require(adminPanel != address(0), "address is zero address");
        _initiatePlatformAccessController(adminPanel);
        _mint(recipient, supply);
    }

    /**
     * @notice Removed the initiate function as recommended and craeted various setters
     */
    function updateVestingAddress(address vesting) external onlyPlatformAdmin {
        require(_vesting == address(0), "already initiated");
        require(vesting != address(0), "cant be zero address");

        _vesting = vesting;
        _accessWhitelistMap[vesting] = true;
    }

    function updateStakingAddress(address staking) external onlyPlatformAdmin {
        require(_staking == address(0), "already initiated");
        require(staking != address(0), "cant be zero address");

        _staking = staking;
        _accessWhitelistMap[staking] = true;

    }

    function updateCashbackAddress(address cashback)
        external
        onlyPlatformAdmin
    {
        require(_cashback == address(0), "already initiated");
        require(cashback != address(0), "cant be zero address");

        _cashback = cashback;
        _accessWhitelistMap[cashback] = true;
    }

    function updateKycstorageAddress(address kycstorage)
        external
        onlyPlatformAdmin
    {
        require(_kycstorage == address(0), "already initiated");
        require(kycstorage != address(0), "cant be zero address");

        _kycstorage = kycstorage;
        _accessWhitelistMap[kycstorage] = true;
    }

    function isAccessWhitelistMember(address wallet)
        external
        view
        returns (bool)
    {
        return _accessWhitelistMap[wallet];
    }

    /**
     * @notice Turn off access confines checking in transfer, by default turn on
     * After can't turn on back, can call only once
     * Only platform admin can do
     */
    function turnOffAccessConfines()
        external
        accessConfinesTurnOn
        onlyPlatformAdmin
    {
        _isAccessConfinesTurnOff = false;

        emit TurnOffAccessConfines(msgSender());
    }

    function insertWalletListToAccessWhitelist(address[] calldata walletList)
        external
        accessConfinesTurnOn
        onlyPlatformAdmin
    {
        require(0 < walletList.length, "wallet list is empty");

        uint256 index = walletList.length;
        while (0 < index) {
            --index;

            _accessWhitelistMap[walletList[index]] = true;
        }

        emit InsertWalletListToAccessWhitelist(msgSender(), walletList);
    }

    function removeWalletListFromAccessWhitelist(address[] calldata walletList)
        external
        accessConfinesTurnOn
        onlyPlatformAdmin
    {
        require(0 < walletList.length, "wallet list is empty");

        uint256 index = walletList.length;
        while (0 < index) {
            --index;

            _accessWhitelistMap[walletList[index]] = false;
        }

        emit RemoveWalletListFromAccessWhitelist(msgSender(), walletList);
    }

    /**
     * @notice Burn tokens from the sender balance
     * Only platform admin can do
     */
    function burn(uint256 amount) external onlyPlatformAdmin {
        _burn(msgSender(), amount);
    }

    /**
     * @dev Similat to transferFrom, but to address is sender
     * Only vesting, staking and cashback contracts can call
     * Designed to save money, transfers without approval
     */
    function specialTransferFrom(
        address from,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        address to = msgSender();

        require(
            to == _vesting || to == _staking || to == _cashback,
            "incorrect sender"
        );

        bool readyForTransfer = transferWithAuthorization(
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        require(readyForTransfer, "EIP3009: invalid signature");

        _transfer(from, to, value);
    }

    /**
     * @dev Call before transfer
     * If access confines turn on transer to contracts which are not in whitelist will revert
     * @param to address to tokens are transferring
     */
    function _beforeTokenTransfer(
        address,
        address to,
        uint256
    ) internal virtual override {
        bool isWallet = !Address.isContract(to);
        if (_isAccessConfinesTurnOff) {
            require(
                isWallet ||
                    _accessWhitelistMap[to] ||
                    IKYCStorage(_kycstorage).checkVerifiedUser(to),
                "incorrect recipent"
            );
        }
    }
}
