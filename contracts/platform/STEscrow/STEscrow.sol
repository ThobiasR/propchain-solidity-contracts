// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/platform/factory/IstFactory/ISTFactory.sol";
import "contracts/platform/sttoken/Isttoken/ISTToken.sol";
import "../access_controller/PlatformAccessController.sol";
import "contracts/platform/KYCStorage/IKYCStorage/IKYCStorage.sol";
import "contracts/platform/STTransferController/ISTTransferController/ISTTransferController.sol";

enum EscrowStatus {
    STARTED,
    OPENED,
    CLOSED,
    FAILED,
    NONE,
    FINISHED
}

contract STEscrow is PlatformAccessController {
    struct EscrowProperties {
        uint256 startTime;
        uint256 openTime;
        uint256 endTime;
        uint256 stAmountForPrice;
        uint256 usdAmountForPrice;
        uint256 softCapInUsd;
        uint256 participateAmountInUsd;
        uint256 withdrawAmountInUsd;
        uint256 claimAmountInUsd;
        uint256 hardCapInUsd;
    }

    struct WalletProperties {
        uint256 stTokenAmount;
        uint256 usdAmount;
    }

    address public tool;
    address public usd;
    address public kycStorage;
    address private sTTransferController;

    mapping(uint256 => EscrowProperties) private _escrowPropertiesMap;
    mapping(uint256 => mapping(address => WalletProperties))
        private _walletPropertiesMap;

    event UpdatedUsdAddress(address indexed usdAddress);

    event UpdatedStFactoryAddress(address indexed factoryAddress);

    event UpdatedKycStorageAddress(address indexed kycStorage);

    event UpdatedStTransferControllerAddress(
        address indexed sTTransferController
    );

    constructor(
        address adminPanel,
        address usd_,
        address tool_,
        address _kycStorage
    ) {
        require(usd_ != address(0), "cant be zero address");
        require(tool_ != address(0), "cant be zero address");
        require(adminPanel != address(0), "address is zero address");
        require(_kycStorage != address(0), "address is zero address");
        _initiatePlatformAccessController(adminPanel);
        usd = usd_;
        tool = tool_;
        kycStorage = _kycStorage;
    }

    function setFactoryAddress(address _tool) external onlyPlatformAdmin {
        require(_tool != address(0), "address is zero address");
        tool = _tool;
        emit UpdatedStFactoryAddress(_tool);
    }

    function setUsdAddress(address _usd) external onlyPlatformAdmin {
        require(_usd != address(0), "address is zero address");
        usd = _usd;
        emit UpdatedUsdAddress(_usd);
    }

    function setKycStorageAddress(address _kycStorage)
        external
        onlyPlatformAdmin
    {
        require(_kycStorage != address(0), "address is zero address");
        kycStorage = _kycStorage;
        emit UpdatedKycStorageAddress(_kycStorage);
    }

    function setSTTransferController(address _sTTransferController)
        external
        onlyPlatformAdmin
    {
        require(_sTTransferController != address(0), "address is zero address");
        sTTransferController = _sTTransferController;
        emit UpdatedStTransferControllerAddress(_sTTransferController);
    }

    function escrowStatusOf(uint256 tokenId, uint256 nowTime)
        external
        view
        returns (EscrowStatus)
    {
        EscrowProperties storage p = _escrowPropertiesMap[tokenId];
        return _escrowStatusOf(p, nowTime);
    }

    function escrowPropertiesOf(uint256 tokenId)
        external
        view
        returns (
            uint256 startTime,
            uint256 endTime,
            uint256 stAmountForPrice,
            uint256 usdAmountForPrice,
            uint256 softCapInUsd,
            uint256 participateAmountInUsd,
            uint256 withdrawAmountInUsd,
            uint256 claimAmountInUsd
        )
    {
        EscrowProperties storage p = _escrowPropertiesMap[tokenId];
        return (
            p.startTime,
            p.endTime,
            p.stAmountForPrice,
            p.usdAmountForPrice,
            p.softCapInUsd,
            p.participateAmountInUsd,
            p.withdrawAmountInUsd,
            p.claimAmountInUsd
        );
    }

    function walletPropertiesOf(uint256 stTokenId, address wallet)
        external
        view
        returns (uint256 stTokenAmount, uint256 usdAmount)
    {
        WalletProperties storage p = _walletPropertiesMap[stTokenId][wallet];
        return (p.stTokenAmount, p.usdAmount);
    }

    function participate(uint256 stTokenId, uint256 usdAmount)
        external
        returns (uint256 tokenAmount)
    {
        EscrowProperties storage p = _escrowPropertiesMap[stTokenId];

        require(
            p.participateAmountInUsd + usdAmount < p.hardCapInUsd,
            "Escrow hardcap will be exceed"
        );

        tokenAmount = (usdAmount * p.stAmountForPrice) / p.usdAmountForPrice;

        address contractAddress = getStTokenContractAddress(stTokenId);

        ISTTransferController(sTTransferController)
            .verifyJurisdictionInvestment(
                msg.sender,
                stTokenId,
                tokenAmount,
                ISTToken(contractAddress).getStTokenPrice(stTokenId)
            );

        require(
            _escrowStatusOf(p, block.timestamp) == EscrowStatus.STARTED,
            "Escrow not started"
        );

        address wallet = msgSender();

        bool isWhiteListed = IKYCStorage(kycStorage).getWhiteListedAddress(
            wallet,
            stTokenId
        );

        if (!isWhiteListed) {
            require(
                _escrowStatusOf(p, block.timestamp) == EscrowStatus.OPENED,
                "Escrow not opened"
            );
        }

        bool state = IERC20(usd).transferFrom(wallet, address(this), usdAmount);

        require(state, "failed transfer");

        p.participateAmountInUsd += usdAmount;

        WalletProperties storage walletProps = _walletPropertiesMap[stTokenId][
            wallet
        ];

        walletProps.stTokenAmount += tokenAmount;
        walletProps.usdAmount += usdAmount;
    }

    function claim(uint256 tokenId) external {
        EscrowProperties storage p = _escrowPropertiesMap[tokenId];
        require(
            _escrowStatusOf(p, block.timestamp) == EscrowStatus.CLOSED,
            "Escrow not closed"
        );

        address wallet = msgSender();
        _claim(p, _walletPropertiesMap[tokenId][wallet], tokenId, wallet);
    }

    function claim(address wallet, uint256 tokenId) external {
        EscrowProperties storage p = _escrowPropertiesMap[tokenId];
        require(
            _escrowStatusOf(p, block.timestamp) == EscrowStatus.CLOSED,
            "Escrow not closed"
        );
        _claim(p, _walletPropertiesMap[tokenId][wallet], tokenId, wallet);
    }

    function claimBatch(address wallet, uint256[] calldata tokenIds) external {
        for (uint8 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            EscrowProperties storage p = _escrowPropertiesMap[tokenId];
            require(
                _escrowStatusOf(p, block.timestamp) == EscrowStatus.CLOSED,
                "Escrow not closed"
            );
            _claim(p, _walletPropertiesMap[tokenId][wallet], tokenId, wallet);
        }
    }

    function claimBatch(
        address[] calldata walletList,
        uint256[][] calldata tokenIds
    ) external {
        require(walletList.length == tokenIds.length, "Incorrect list size");

        for (uint8 i = 0; i < walletList.length; ++i) {
            address currentWallet = walletList[i];
            for (uint8 j = 0; j < tokenIds[i].length; ++j) {
                uint256 tokenId = tokenIds[i][j];
                EscrowProperties storage p = _escrowPropertiesMap[tokenId];
                require(
                    _escrowStatusOf(p, block.timestamp) == EscrowStatus.CLOSED,
                    "Escrow not closed"
                );
                _claim(
                    p,
                    _walletPropertiesMap[tokenId][currentWallet],
                    tokenId,
                    currentWallet
                );
            }
        }
    }

    function claimForWalletList(uint256 tokenId, address[] calldata walletList)
        external
    {
        EscrowProperties storage p = _escrowPropertiesMap[tokenId];
        require(
            _escrowStatusOf(p, block.timestamp) == EscrowStatus.CLOSED,
            "EscrowStatus not CLOSED"
        );

        address wallet;
        mapping(address => WalletProperties)
            storage wMap = _walletPropertiesMap[tokenId];

        for (uint256 i = 0; i < walletList.length; ++i) {
            wallet = walletList[i];
            _claim(p, wMap[wallet], tokenId, wallet);
        }
    }

    function withdraw(uint256 tokenId) external {
        EscrowProperties storage p = _escrowPropertiesMap[tokenId];
        require(
            _escrowStatusOf(p, block.timestamp) == EscrowStatus.FAILED,
            "EscrowStatus not FAILED"
        );

        address wallet = msgSender();

        _withdraw(p, _walletPropertiesMap[tokenId][wallet], tokenId, wallet);

        _afterWithdraw(p, tokenId);
    }

    function withdrawForWalletList(
        uint256 tokenId,
        address[] calldata walletList
    ) external {
        EscrowProperties storage p = _escrowPropertiesMap[tokenId];
        require(
            _escrowStatusOf(p, block.timestamp) == EscrowStatus.FAILED,
            "EscrowStatus not FAILED"
        );

        address wallet;
        mapping(address => WalletProperties)
            storage wMap = _walletPropertiesMap[tokenId];
        for (uint256 i = 0; i < walletList.length; ++i) {
            wallet = walletList[i];
            _withdraw(p, wMap[wallet], tokenId, wallet);
        }

        _afterWithdraw(p, tokenId);
    }

    function startEscrow(
        uint256 stTokenId,
        uint256 startTime,
        uint256 endTime,
        uint256 openTime,
        uint256 stAmountForPrice,
        uint256 usdAmountForPrice,
        uint256 softCapInUsd,
        uint256 hardCapInUsd
    ) external {
        require(msg.sender == tool, "unauthorized caller");

        require(
            block.timestamp < endTime && startTime < endTime,
            "Incorrect start or end time"
        );

        require(
            startTime < openTime && openTime < endTime,
            "Incorrect open time"
        );

        require(
            0 < stAmountForPrice && 0 < usdAmountForPrice && 0 < softCapInUsd,
            "Values must be more 0"
        );

        EscrowProperties storage p = _escrowPropertiesMap[stTokenId];

        require(
            _escrowStatusOf(p, block.timestamp) == EscrowStatus.NONE,
            "Incorrect escrow status"
        );

        p.startTime = startTime;
        p.endTime = endTime;
        p.openTime = openTime;
        p.stAmountForPrice = stAmountForPrice;
        p.usdAmountForPrice = usdAmountForPrice;
        p.softCapInUsd = softCapInUsd;
        p.hardCapInUsd = hardCapInUsd;
    }

    function _escrowStatusOf(EscrowProperties storage p, uint256 nowTime)
        private
        view
        returns (EscrowStatus)
    {
        if (p.startTime == p.endTime) {
            return EscrowStatus.NONE;
        } else if (p.startTime < nowTime && nowTime < p.openTime) {
            return EscrowStatus.STARTED;
        } else if (p.openTime < nowTime) {
            return EscrowStatus.OPENED;
        } else if (
            p.endTime < nowTime && p.participateAmountInUsd < p.softCapInUsd
        ) {
            return EscrowStatus.FAILED;
        } else if (
            p.endTime < nowTime && p.participateAmountInUsd > p.claimAmountInUsd
        ) {
            return EscrowStatus.CLOSED;
        } else {
            return EscrowStatus.FINISHED;
        }
    }

    function _claim(
        EscrowProperties storage p,
        WalletProperties storage w,
        uint256 stTokenId,
        address wallet
    ) private {
        address contractAddress = getStTokenContractAddress(stTokenId);

        require(w.stTokenAmount > 0, "invalid amount");

        ISTToken(contractAddress).mintToken(wallet, stTokenId, w.stTokenAmount);

        p.claimAmountInUsd += w.usdAmount;

        delete _walletPropertiesMap[stTokenId][wallet];
    }

    function getStTokenContractAddress(uint256 _stTokenId)
        internal
        view
        returns (address)
    {
        return ISTFactory(tool).checkStEntityToken(_stTokenId);
    }

    function _withdraw(
        EscrowProperties storage p,
        WalletProperties storage w,
        uint256 tokenId,
        address wallet
    ) private {
        uint256 usdAmount = w.usdAmount;

        p.withdrawAmountInUsd += usdAmount;
        delete _walletPropertiesMap[tokenId][wallet];

        bool state = IERC20(usd).transfer(wallet, usdAmount);

        require(state, "failed transfer");
    }

    function _afterWithdraw(EscrowProperties storage p, uint256 tokenId)
        private
    {
        if (p.participateAmountInUsd == p.withdrawAmountInUsd) {
            delete _escrowPropertiesMap[tokenId];
        }
    }

    function cancelEscrow(uint256 tokenId) external {
        require(msg.sender == tool, "unauthorized caller");

        EscrowProperties storage p = _escrowPropertiesMap[tokenId];

        require(
            _escrowStatusOf(p, block.timestamp) == EscrowStatus.STARTED,
            "Escrow is opened"
        );

        _afterWithdraw(p, tokenId);
    }
}
