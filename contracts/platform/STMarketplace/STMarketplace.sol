// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/platform/factory/IstFactory/ISTFactory.sol";
import "../access_controller/PlatformAccessController.sol";

enum OrderSide {
    BUY,
    SELL
}

contract STMarketplace is PlatformAccessController {
    struct Order {
        uint256 orderId;
        OrderSide side;
        uint256 stId;
        uint256 stAmount;
        address paymentToken;
        uint256 paymentTokenAmount;
        address[] targetUser;
        bool isClose;
        address owner;
    }

    struct Swap {
        uint256 swapId;
        uint256 fromStId;
        uint256 fromStAmount;
        uint256 toStId;
        uint256 toStAmount;
        address[] targetUser;
        bool isClose;
        address owner;
    }

    uint256 private _lastOrderId;
    uint256 private _lastSwapId;

    address public stTokenFactory;

    mapping(uint256 => Order) private _orderMapping;
    mapping(uint256 => Swap) private _swapMapping;

    event OpenOrder(
        uint256 orderId,
        address indexed owner,
        address[] indexed targetUser
    );

    event UpdateOrder(
        uint256 orderId,
        OrderSide side,
        uint256 stId,
        uint256 stAmount,
        address indexed paymentToken,
        uint256 paymentTokenAmount
    );

    event CloseOrder(uint256 orderId);

    event CancelOrder(uint256 orderId);

    event OpenSwap(
        uint256 orderId,
        address indexed owner,
        address[] indexed targetUser
    );

    event UpdateSwap(
        uint256 fromStId,
        uint256 fromStAmount,
        uint256 toStId,
        uint256 toStAmount
    );

    event CloseSwap(uint256 orderId);

    event CancelSwap(uint256 orderId);

    event UpdatedStFactoryAddress(address indexed factoryAddress);

    constructor(address _stTokenFactory) {
        require(_stTokenFactory != address(0), "cant be zero address");
        stTokenFactory = _stTokenFactory;
    }

    function setFactoryAddress(address _stTokenFactory)
        external
        onlyPlatformAdmin
    {
        require(_stTokenFactory != address(0), "address is zero address");
        stTokenFactory = _stTokenFactory;
        emit UpdatedStFactoryAddress(_stTokenFactory);
    }

    function orderOf(uint256 orderId)
        external
        view
        returns (
            OrderSide side,
            uint256 stId,
            uint256 stAmount,
            address paymentToken,
            uint256 paymentTokenAmount,
            address owner,
            address[] memory targetUser
        )
    {
        Order storage order = _orderMapping[orderId];

        require(order.isClose, "order is closed");

        return (
            order.side,
            order.stId,
            order.stAmount,
            order.paymentToken,
            order.paymentTokenAmount,
            order.owner,
            order.targetUser
        );
    }

    function swapOf(uint256 swapId)
        external
        view
        returns (
            uint256 fromStId,
            uint256 fromStAmount,
            uint256 toStId,
            uint256 toStAmount,
            address owner,
            address[] memory targetUser
        )
    {
        Swap storage swap = _swapMapping[swapId];

        require(swap.isClose, "swap is closed");

        return (
            swap.fromStId,
            swap.fromStAmount,
            swap.toStId,
            swap.toStAmount,
            swap.owner,
            swap.targetUser
        );
    }

    function openOrder(
        OrderSide side,
        uint256 stId,
        uint256 stAmount,
        address paymentToken,
        uint256 paymentTokenAmount,
        address[] calldata targetUser
    ) external returns (uint256 id) {
        _lastOrderId++;

        address stAddress = ISTFactory(stTokenFactory).checkStEntityToken(stId);

        if (side == OrderSide.SELL) {
            IERC1155(stAddress).safeTransferFrom(
                msg.sender,
                address(this),
                stId,
                stAmount,
                ""
            );
        }
        if (side == OrderSide.BUY) {
            bool state = IERC20(paymentToken).transferFrom(
                msg.sender,
                address(this),
                paymentTokenAmount
            );
            require(state, "failed transfer");
        }

        _orderMapping[_lastOrderId] = Order(
            _lastOrderId,
            side,
            stId,
            stAmount,
            paymentToken,
            paymentTokenAmount,
            targetUser,
            false,
            msg.sender
        );

        emit OpenOrder(_lastOrderId, msg.sender, targetUser);

        emit UpdateOrder(
            _lastOrderId,
            side,
            stId,
            stAmount,
            paymentToken,
            paymentTokenAmount
        );

        return _lastOrderId;
    }

    function openSwap(
        uint256 fromStId,
        uint256 fromStAmount,
        uint256 toStId,
        uint256 toStAmount,
        address[] calldata targetUser
    ) external returns (uint256 id) {
        _lastSwapId++;

        address stAddress = ISTFactory(stTokenFactory).checkStEntityToken(
            fromStId
        );

        IERC1155(stAddress).safeTransferFrom(
            msg.sender,
            address(this),
            fromStId,
            fromStAmount,
            ""
        );

        _swapMapping[_lastSwapId] = Swap(
            _lastSwapId,
            fromStId,
            fromStAmount,
            toStId,
            toStAmount,
            targetUser,
            false,
            msg.sender
        );

        emit OpenSwap(_lastSwapId, msg.sender, targetUser);

        emit UpdateSwap(fromStId, fromStAmount, toStId, toStAmount);

        return _lastSwapId;
    }

    function checkTargetUser(
        address sender,
        uint256 listLength,
        address[] memory targetList
    ) internal pure returns (bool result) {
        while (0 < listLength) {
            listLength--;
            if (sender == targetList[listLength]) {
                return true;
            }
        }
        return false;
    }

    function executeOrder(uint256 orderId, uint256 stAmount) external {
        Order storage order = _orderMapping[orderId];
        uint256 targetListLength = order.targetUser.length;

        if (targetListLength > 0) {
            require(
                checkTargetUser(msg.sender, targetListLength, order.targetUser),
                "invalid target user"
            );
        }

        require(!order.isClose, "order is closed");

        require(order.owner != address(0), "invalid order owner");

        require(
            stAmount <= order.stAmount,
            "Insufficient Tokens Amount At Order"
        );

        uint256 currentPrice = order.paymentTokenAmount * stAmount;

        uint256 erc20Amount = currentPrice / order.stAmount;

        address stAddress = ISTFactory(stTokenFactory).checkStEntityToken(
            order.stId
        );

        if (order.side == OrderSide.SELL) {
            bool state = IERC20(order.paymentToken).transferFrom(
                msg.sender,
                order.owner,
                erc20Amount
            );
            require(state, "failed transfer");
            IERC1155(stAddress).safeTransferFrom(
                address(this),
                msg.sender,
                order.stId,
                stAmount,
                ""
            );
        }
        if (order.side == OrderSide.BUY) {
            bool state = IERC20(order.paymentToken).transferFrom(
                address(this),
                msg.sender,
                erc20Amount
            );
            require(state, "failed transfer");
            IERC1155(stAddress).safeTransferFrom(
                msg.sender,
                order.owner,
                order.stId,
                stAmount,
                ""
            );
        }

        order.stAmount -= stAmount;
        order.paymentTokenAmount -= erc20Amount;

        emit UpdateOrder(
            order.orderId,
            order.side,
            order.stId,
            order.stAmount,
            order.paymentToken,
            order.paymentTokenAmount
        );

        if (order.stAmount == 0) {
            order.isClose = true;
            emit CloseOrder(order.orderId);
            delete _orderMapping[orderId];
        }
    }

    function executeSwap(uint256 swapId, uint256 stAmount) external {
        Swap storage swap = _swapMapping[swapId];

        uint256 targetListLength = swap.targetUser.length;

        if (targetListLength > 0) {
            require(
                checkTargetUser(msg.sender, targetListLength, swap.targetUser),
                "invalid target user"
            );
        }

        require(!swap.isClose, "swap is closed");

        require(swap.owner != address(0), "invalid swap owner");

        require(
            stAmount <= swap.fromStAmount,
            "Insufficient Tokens Amount At Order"
        );

        uint256 currentStPrice = swap.fromStAmount * stAmount;
        uint256 toStAmount = currentStPrice / swap.toStAmount;

        address fromStAddress = ISTFactory(stTokenFactory).checkStEntityToken(
            swap.fromStId
        );

        address toStAddress = ISTFactory(stTokenFactory).checkStEntityToken(
            swap.toStId
        );

        IERC1155(fromStAddress).safeTransferFrom(
            address(this),
            msg.sender,
            swap.fromStId,
            stAmount,
            ""
        );
        IERC1155(toStAddress).safeTransferFrom(
            msg.sender,
            swap.owner,
            swap.toStId,
            toStAmount,
            ""
        );

        swap.fromStAmount -= stAmount;
        swap.toStAmount -= toStAmount;

        emit UpdateSwap(
            swap.fromStId,
            swap.fromStAmount,
            swap.toStId,
            swap.toStAmount
        );

        if (swap.fromStAmount == 0) {
            emit CloseSwap(swapId);
            delete _swapMapping[swapId];
        }
    }

    function cancelOrder(uint256 orderId) external {
        Order storage order = _orderMapping[orderId];

        require(order.owner != address(0), "invalid order owner");

        require(order.owner == msg.sender, "not order owner");

        require(!order.isClose, "order is closed");

        address stAddress = ISTFactory(stTokenFactory).checkStEntityToken(
            order.stId
        );

        if (order.side == OrderSide.SELL) {
            IERC1155(stAddress).safeTransferFrom(
                address(this),
                msg.sender,
                order.stId,
                order.stAmount,
                ""
            );
        }
        if (order.side == OrderSide.BUY) {
            bool state = IERC20(order.paymentToken).transferFrom(
                address(this),
                msg.sender,
                order.paymentTokenAmount
            );

            require(state, "failed transfer");
        }

        emit CancelOrder(orderId);
        delete _orderMapping[orderId];
    }

    function cancelSwap(uint256 swapId) external {
        Swap storage swap = _swapMapping[swapId];

        require(swap.owner != address(0), "invalid swap owner");

        require(swap.owner == msg.sender, "not swap owner");

        require(!swap.isClose, "swap is closed");

        address stAddress = ISTFactory(stTokenFactory).checkStEntityToken(
            swap.fromStId
        );

        IERC1155(stAddress).safeTransferFrom(
            address(this),
            msg.sender,
            swap.fromStId,
            swap.fromStAmount,
            ""
        );

        emit CancelSwap(swapId);
        delete _swapMapping[swapId];
    }
}
