// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ISTFactory {
    /**
     * @dev Return entity properties
     * @param companyAddress The address of wallet that created token
     **/

    function tokenPropertiesOf(address _companyAddress)
        external
        view
        returns (
            address companyAddress,
            uint256 companyId,
            string memory companyName,
            address stToken
        );

    function checkStEntityToken(uint256 _token) external view returns (address);
}
