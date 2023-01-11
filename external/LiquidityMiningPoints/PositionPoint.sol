// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "../../interfaces/IAntfarmPosition.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PositionPoint is Ownable {
    address public immutable liquidityMining;
    address public immutable antfarmPositions;

    mapping(address => bool) public pairBlacklist;
    mapping(uint256 => uint256) public positionLastRegister;

    event Blacklist(address pair, bool blacklisted);

    error NotAllowed();

    constructor(address _liquidityMining, address _antfarmPositions) {
        require(_liquidityMining != address(0), "NULL_LM_ADDRESS");
        require(_antfarmPositions != address(0), "NULL_POS_ADDRESS");
        liquidityMining = _liquidityMining;
        antfarmPositions = _antfarmPositions;
    }

    struct PairBlacklist {
        address pair;
        bool blacklisted;
    }

    function setBlacklist(PairBlacklist[] calldata pairsBlacklist)
        external
        onlyOwner
    {
        uint256 pairsLength = pairsBlacklist.length;
        for (uint256 i; i < pairsLength; ++i) {
            pairBlacklist[pairsBlacklist[i].pair] = pairsBlacklist[i]
                .blacklisted;
            emit Blacklist(
                pairsBlacklist[i].pair,
                pairsBlacklist[i].blacklisted
            );
        }
    }

    function savePoints(
        uint256 _currentPeriod,
        address _address,
        uint256[] memory _positionsIds
    ) external returns (uint256 points) {
        if (msg.sender != liquidityMining) revert NotAllowed();
        uint256 numPositions = _positionsIds.length;

        if (numPositions > 0) {
            IAntfarmPosition positionsContract = IAntfarmPosition(
                antfarmPositions
            );
            IAntfarmPosition.PositionDetails[]
                memory positions = positionsContract.getPositionsDetails(
                    _positionsIds
                );

            for (uint256 i; i < numPositions; ++i) {
                if (
                    (_address == positions[i].owner ||
                        _address == positions[i].delegate) &&
                    !pairBlacklist[positions[i].pair]
                ) {
                    if (
                        positionLastRegister[positions[i].id] < _currentPeriod
                    ) {
                        points = points + positions[i].dividend;

                        positionLastRegister[positions[i].id] = _currentPeriod;
                    }
                }
            }
        }
    }

    function getPoints(
        uint256 _currentPeriod,
        address _address,
        uint256[] memory _positionsIds
    ) external view returns (uint256 points) {
        if (msg.sender != liquidityMining) revert NotAllowed();
        uint256 numPositions = _positionsIds.length;

        if (numPositions > 0) {
            IAntfarmPosition positionsContract = IAntfarmPosition(
                antfarmPositions
            );
            IAntfarmPosition.PositionDetails[]
                memory positions = positionsContract.getPositionsDetails(
                    _positionsIds
                );

            for (uint256 i; i < numPositions; ++i) {
                if (
                    (_address == positions[i].owner ||
                        _address == positions[i].delegate) &&
                    !pairBlacklist[positions[i].pair]
                ) {
                    if (
                        positionLastRegister[positions[i].id] < _currentPeriod
                    ) {
                        points = points + positions[i].dividend;
                    }
                }
            }
        }
    }
}
