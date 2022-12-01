// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../interfaces/IERC20.sol";
import "../libraries/TransferHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AntfarmLinearSale is Ownable {
    address public immutable antfarmToken;
    address public quoteToken;

    uint256 public lowerPrice;
    uint256 public higherPrice;

    uint256 public constant INITIAL_RESERVE = 10 * 10**5 * 10**18; // 1M tokens

    event Buy(address buyer, uint256 amount, uint256 cost);

    constructor(
        address _antfarmToken,
        address _quoteToken,
        uint256 _lowerPrice,
        uint256 _higherPrice
    ) {
        require(_antfarmToken != address(0), "NULL_ATF_ADDRESS");
        require(_quoteToken != address(0), "NULL_QUOTE_ADDRESS");
        antfarmToken = _antfarmToken;
        quoteToken = _quoteToken;
        lowerPrice = _lowerPrice;
        higherPrice = _higherPrice;
    }

    function buyTokens(uint256 _amount, uint256 _maxCost) external {
        uint256 reserve = IERC20(antfarmToken).balanceOf(address(this));
        require(reserve > 0, "SALE_IS_OVER");
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
            10**IERC20(quoteToken).decimals();
        require(totalCost <= _maxCost, "COST_LIMIT_EXCEDED");

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

    function getAveragePriceForAmount(uint256 _amount)
        external
        view
        returns (uint256 averagePrice)
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

        averagePrice = (startPrice + endPrice) / 2;
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

    function withdrawToken(address _token, uint256 _amount) external onlyOwner {
        TransferHelper.safeTransfer(_token, owner(), _amount);
    }

    function withdrawTotalTokenBalance(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        TransferHelper.safeTransfer(_token, owner(), amount);
    }
}
