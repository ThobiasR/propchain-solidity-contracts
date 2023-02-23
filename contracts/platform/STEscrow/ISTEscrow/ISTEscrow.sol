// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ISTEscrow {
    function cancelEscrow(uint256 tokenId) external;

    function startEscrow(
        uint256 stTokenId,
        uint256 startTime,
        uint256 endTime,
        uint256 stAmountForPrice,
        uint256 usdAmountForPrice,
        uint256 softCapInUsd
    ) external;
}
