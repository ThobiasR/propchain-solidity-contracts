// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../admin_panel/PlatformAdminPanel.sol";

/**
 * @title Abstract contract from which platform contracts with admin function are inherited
 * @dev Contains the platform admin panel
 * Contains modifier that checks whether sender is platform admin, use platform admin panel
 */
abstract contract PlatformAccessController {
    address public _panel;

    function _initiatePlatformAccessController(address adminPanel) internal {
        require(address(_panel) == address(0), "PAC: already initiate");

        _panel = adminPanel;
    }

    /**
     * @dev Modifier that makes function available for platform admins only
     */
    modifier onlyPlatformAdmin() {
        require(
            PlatformAdminPanel(_panel).isAdmin(msgSender()),
            "PAC: caller is not admin"
        );
        _;
    }

    function msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}
