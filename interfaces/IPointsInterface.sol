// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

interface IPointsInterface {
    function savePoints(
        uint256 _currentPeriod,
        address _address,
        uint256[] memory _positionsIds
    ) external returns (uint256 points);

    function getPoints(
        uint256 _currentPeriod,
        address _address,
        uint256[] memory _positionsIds
    ) external view returns (uint256 points);
}
