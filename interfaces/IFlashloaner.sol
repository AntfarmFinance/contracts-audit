// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IFlashloaner {
    function flashloan(uint256 amount, bytes calldata data) external;

    function wFlashloan(uint256 wAmount, bytes calldata data) external;
}
