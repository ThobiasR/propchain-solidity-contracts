// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../../access_controller/PlatformAccessController.sol";
import "./IPlatformTokenPriceProvider.sol";

/**
 * @title Implementations of pricing should inherit
 * @notice After deployment, you must set poolProvider or hardcodeProvider
 * In the future, you can reset provider, the last setted will be active
 */
contract PlatformTokenPriceProvider is
    PlatformAccessController,
    IPlatformTokenPriceProvider
{
    /**
     * @notice Emit during poolProvider set process
     * @param admin Platform admin which do this action
     * @param provider price provider that analyzes a certain swap pool
     * Must implement IPlatformTokenPriceProvider
     */
    event SetPoolProvider(address indexed admin, address provider);

    /**
     * @notice Emit during poolProvider set process
     * @param admin Platform admin which do this action
     * @param swapUsdAmount Min USD amount which can swap to PROP (swapTokenAmount)
     * @param swapTokenAmount Min PROP amount which can swap to USD (swapUsdAmount)
     */
    event SetHardcodeProvider(
        address indexed admin,
        uint256 swapUsdAmount,
        uint256 swapTokenAmount
    );

    enum ProviderState {
        NONE,
        POOL_PROVIDER,
        HARDCODE_PROVIDER
    }

    struct HardcodeProvider {
        uint256 usdAmount;
        uint256 tokenAmount;
    }

    ProviderState private _state;

    address private _poolProvider;

    HardcodeProvider private _hardcodeProvider;

    /**
     * @param adminPanel platform admin panel address
     */
    constructor(address adminPanel) {
        _initiatePlatformAccessController(adminPanel);
    }

    /**
     * @notice Returns the cost of the entered number of PROP in USD
     * Will revert if any provider was not set
     * @param prop number of PROP (1 PROP == 10^18)
     * @return usdAmount number of USD (1 USD == 10^18)
     */
    function usdAmount(uint256 prop) external view override returns (uint256) {
        ProviderState state = _state;

        if (state == ProviderState.POOL_PROVIDER) {
            return IPlatformTokenPriceProvider(_poolProvider).usdAmount(prop);
        }

        if (state == ProviderState.HARDCODE_PROVIDER) {
            HardcodeProvider storage p = _hardcodeProvider;
            return (prop * p.usdAmount) / p.tokenAmount;
        }

        revert("any provider was not set");
    }

    /**
     * @notice Returns the cost of the entered number of USD in PROP
     * Will revert if any provider was not set
     * @param usd number of USD (1 USD == 10^18)
     * @return tokenAmount number of PROP (1 PROP == 10^18)
     */
    function tokenAmount(uint256 usd) external view override returns (uint256) {
        ProviderState state = _state;

        if (state == ProviderState.POOL_PROVIDER) {
            return IPlatformTokenPriceProvider(_poolProvider).tokenAmount(usd);
        }

        if (state == ProviderState.HARDCODE_PROVIDER) {
            HardcodeProvider storage p = _hardcodeProvider;
            return (usd * p.tokenAmount) / p.usdAmount;
        }

        revert("any provider was not set");
    }

    /**
     * @notice Return value depends on which provider was set last
     * Return ProviderState.NONE (0) if any provider was not set
     * Return ProviderState.POOL_PROVIDER (1) if poolProvider was set as last
     * Return ProviderState.HARDCODE_PROVIDER (2) if hardcodeProvider was set as last
     */
    function providerState() external view returns (ProviderState) {
        return _state;
    }

    /**
     * @notice Will revert if poolProvider was not set as last (providerState() != 1)
     * @return provider price provider that analyzes a certain swap pool
     * Must implement IPlatformTokenPriceProvider
     */
    function poolProvider() external view returns (address) {
        require(_state == ProviderState.POOL_PROVIDER, "incorrect state");

        return _poolProvider;
    }

    /**
     * @notice Will revert if hardcodeProvider was not set as last (providerState() != 2)
     * @return swapUsdAmount Min USD amount which can swap to PROP (swapTokenAmount)
     * @return swapTokenAmount Min PROP amount which can swap to USD (swapUsdAmount)
     */
    function hardcodeProvider()
        external
        view
        returns (uint256 swapUsdAmount, uint256 swapTokenAmount)
    {
        require(_state == ProviderState.HARDCODE_PROVIDER, "incorrect state");

        HardcodeProvider storage p = _hardcodeProvider;
        swapUsdAmount = p.usdAmount;
        swapTokenAmount = p.tokenAmount;
    }

    /**
     * @notice Only platform admin can do
     */
    function setPoolProvider(address provider) external onlyPlatformAdmin {
        _setPoolProvider(provider);
    }

    /**
     * @notice Only platform admin can do
     */
    function setHardcodeProvider(uint256 swapUsdAmount, uint256 swapTokenAmount)
        external
        onlyPlatformAdmin
    {
        _setHardcodeProvider(swapUsdAmount, swapTokenAmount);
    }

    function _setPoolProvider(address provider) private {
        _state = ProviderState.POOL_PROVIDER;

        _poolProvider = provider;

        emit SetPoolProvider(msgSender(), provider);
    }

    function _setHardcodeProvider(
        uint256 swapUsdAmount,
        uint256 swapTokenAmount
    ) private {
        require(0 < swapUsdAmount && 0 < swapTokenAmount, "incorrect input");

        _state = ProviderState.HARDCODE_PROVIDER;

        HardcodeProvider storage p = _hardcodeProvider;
        p.usdAmount = swapUsdAmount;
        p.tokenAmount = swapTokenAmount;

        emit SetHardcodeProvider(msgSender(), swapUsdAmount, swapTokenAmount);
    }
}
