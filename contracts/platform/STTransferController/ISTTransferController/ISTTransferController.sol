// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ISTTransferController {
    /**
     * @dev add a jurisdiction limit
     * @param _jurisdiction jurisdiction identifier
     * @param _limit jurisdiction limit
     **/
    function addJurisdictionLimt(
        uint256 _token,
        uint256[] memory _jurisdiction,
        uint256[] memory _limit
    ) external;

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
    ) external;

    function setWhitelistedContracts(address whiteListAddress) external;

    function verifyJurisdictionInvestment(
        address _user,
        uint256 _token,
        uint256 _amount,
        uint256 _price
    ) external view returns (uint256);
}
