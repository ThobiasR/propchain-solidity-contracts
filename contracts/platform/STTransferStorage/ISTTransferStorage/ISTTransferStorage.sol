// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ISTTransferStorage {
    /**
     * @dev this function gets the current allowance of user
     * @param _user address of user
     * @param _token token id to map to
     **/
    function getUserAllowance(address _user, uint256 _token)
        external
        view
        returns (uint256);

    /**
     * @dev this function updates variables according to transfer
     * @dev this function checks if trasnfer is from escrow contract || token contract ( can be reviewed )
     * @param _to address of user
     * @param _from address of sender
     * @param _token token to be transferred
     * @param _amount price for token
     * @param _toJurisdiction jurisdiction that recieves token
     **/
    function transfer(
        address _to,
        address _from,
        uint256 _token,
        uint256 _amount,
        uint256 _price,
        uint256 _toJurisdiction
    ) external;

    /**
     * @dev this function gets the current allowance of jurisdiaction on a property
     * @param _token token id to map to
     * @param _jurisdiction
     **/
    function getpropertyJurisdictionInvestment(
        uint256 _token,
        uint256 _jurisdiction
    ) external view returns (uint256);
}
