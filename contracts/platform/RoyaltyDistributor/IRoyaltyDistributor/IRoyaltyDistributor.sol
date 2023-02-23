// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IRoyaltyDistributor {
    function addMaxPropertySupply(uint256 _property, uint256 _maxSupply)
        external;

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
    ) external;
}
