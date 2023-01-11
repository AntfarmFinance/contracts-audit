// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/TransferHelper.sol";
import "../interfaces/IERC20.sol";

contract OwnableWithdrawable is Ownable {
    function withdrawToken(address _token, uint256 _amount) external onlyOwner {
        TransferHelper.safeTransfer(_token, owner(), _amount);
    }

    function withdrawTotalTokenBalance(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        TransferHelper.safeTransfer(_token, owner(), amount);
    }
}
