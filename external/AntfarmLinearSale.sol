// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "../libraries/OwnableWithdrawable.sol";
import "../libraries/TransferHelper.sol";
import "../interfaces/IERC20.sol";

contract AntfarmLinearSale is OwnableWithdrawable {
    address public immutable antfarmToken;
    uint256 public immutable startTime;

    address public quoteToken;
    uint256 public lowerPrice;
    uint256 public higherPrice;

    uint256 public constant INITIAL_RESERVE = 1_000_000 * 10**18;

    event Buy(address buyer, uint256 amount, uint256 cost);

    error SaleHasNotStarted();
    error SaleIsOver();
    error CostLimitExceeded();

    constructor(
        address _antfarmToken,
        address _quoteToken,
        uint256 _lowerPrice,
        uint256 _higherPrice,
        uint256 _startTime
    ) {
        require(_antfarmToken != address(0), "NULL_ATF_ADDRESS");
        require(_quoteToken != address(0), "NULL_QUOTE_ADDRESS");
        antfarmToken = _antfarmToken;
        quoteToken = _quoteToken;
        lowerPrice = _lowerPrice;
        higherPrice = _higherPrice;
        startTime = _startTime;
    }

    function buyTokens(uint256 _amount, uint256 _maxCost) external {
        if (startTime > block.timestamp) revert SaleHasNotStarted();

        uint256 reserve = IERC20(antfarmToken).balanceOf(address(this));
        if (reserve == 0) revert SaleIsOver();
        if (reserve > INITIAL_RESERVE) {
            reserve = INITIAL_RESERVE;
        }

        uint256 startAmount = INITIAL_RESERVE - reserve;
        uint256 endAmount = startAmount + _amount;

        uint256 startPrice = (((startAmount * 10**9) / INITIAL_RESERVE) *
            (higherPrice - lowerPrice)) /
            10**9 +
            lowerPrice;
        uint256 endPrice = (((endAmount * 10**9) / INITIAL_RESERVE) *
            (higherPrice - lowerPrice)) /
            10**9 +
            lowerPrice;

        uint256 averagePrice = (startPrice + endPrice) / 2;
        uint256 totalCost = (_amount * averagePrice) /
            10**IERC20(antfarmToken).decimals();

        if (totalCost > _maxCost) revert CostLimitExceeded();

        TransferHelper.safeTransferFrom(
            quoteToken,
            msg.sender,
            address(this),
            totalCost
        );
        TransferHelper.safeTransfer(antfarmToken, msg.sender, _amount);
        emit Buy(msg.sender, _amount, totalCost);
    }

    function getPrice() external view returns (uint256 price) {
        uint256 reserve = IERC20(antfarmToken).balanceOf(address(this));
        if (reserve > INITIAL_RESERVE) {
            reserve = INITIAL_RESERVE;
        }
        uint256 amountLeft = INITIAL_RESERVE - reserve;

        price =
            (((amountLeft * 10**9) / INITIAL_RESERVE) *
                (higherPrice - lowerPrice)) /
            10**9 +
            lowerPrice;
    }

    function getCostForAmount(uint256 _amount)
        external
        view
        returns (uint256 totalCost)
    {
        uint256 reserve = IERC20(antfarmToken).balanceOf(address(this));
        if (reserve > INITIAL_RESERVE) {
            reserve = INITIAL_RESERVE;
        }

        uint256 startAmount = INITIAL_RESERVE - reserve;
        uint256 endAmount = startAmount + _amount;

        uint256 startPrice = (((startAmount * 10**9) / INITIAL_RESERVE) *
            (higherPrice - lowerPrice)) /
            10**9 +
            lowerPrice;
        uint256 endPrice = (((endAmount * 10**9) / INITIAL_RESERVE) *
            (higherPrice - lowerPrice)) /
            10**9 +
            lowerPrice;

        uint256 averagePrice = (startPrice + endPrice) / 2;
        totalCost =
            (_amount * averagePrice) /
            10**IERC20(antfarmToken).decimals();
    }

    function updateDetails(
        address _quoteToken,
        uint256 _lowerPrice,
        uint256 _higherPrice
    ) external onlyOwner {
        quoteToken = _quoteToken;
        lowerPrice = _lowerPrice;
        higherPrice = _higherPrice;
    }
}
