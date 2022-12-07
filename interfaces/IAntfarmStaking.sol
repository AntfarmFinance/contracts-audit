// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IAntfarmStaking {
    function depositVested(address _for, uint256 _amount) external;
}
