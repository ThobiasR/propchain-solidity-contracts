// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ISTToken {
    /**
     * @dev this mints token from an entity contract address
     * @param to The address of wallet to recieve
     * @param stTokedId The id of token to be minted
     * @param amount The amount tokens to be minted
     **/

    function mintToken(
        address to,
        uint256 stTokedId,
        uint256 amount
    ) external;

    function getSTokenIdDataMap(uint256 id)
        external
        view
        returns (
            uint256 _id,
            uint256 _supply,
            string memory _name
        );

    function createToken(
        uint256 _id,
        uint256 _supply,
        string calldata _name,
        uint256 _softCap,
        uint256 _jurisdiction,
        uint256 _price
    ) external;

    function aunthenticateEscrow(uint256 _token, address _sender)
        external
        view
        returns (bool);

    function getStTokenPrice(uint256 _token) external view returns (uint256);
}
