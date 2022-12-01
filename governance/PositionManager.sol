// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../interfaces/IAntfarmPosition.sol";
import "../interfaces/IERC20.sol";
import "../libraries/TransferHelper.sol";
import "../utils/PositionManagerErrors.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @title DAO positions manager
/// @author Antfarm team
/// @notice Manages DAO's position and decides reward fee split allocation
contract PositionManager is Ownable {
    address public immutable antfarmPositions;
    address public immutable antfarmToken;

    address[5] public payees;
    uint256[5] public shares;
    uint256 public totalShares;
    uint256 public executorShare;

    constructor(
        address _antfarmPositions,
        address _antfarmToken,
        uint256 _executorShare
    ) {
        antfarmPositions = _antfarmPositions;
        antfarmToken = _antfarmToken;
        executorShare = _executorShare;
    }

    /// @notice Check if an address is part of payees
    /// @param _address address to check
    /// @return found
    function checkAllocation(address _address)
        public
        view
        returns (bool found)
    {
        for (uint8 i; i < 5; i++) {
            if (payees[i] == _address) {
                found = true;
            }
        }
    }

    /// @notice Update allocation rate for transaction executor
    /// @param _share executor share
    function updateExecutorShare(uint256 _share) external onlyOwner {
        executorShare = _share;
    }

    /// @notice Update allocation rate for a specific payee
    /// @param _address Address for the payee
    /// @param _points allocation points
    function updateAllocation(address _address, uint256 _points)
        public
        onlyOwner
    {
        bool hasAllocation = checkAllocation(_address);
        if (!hasAllocation && _points == 0) revert NullNewAllocation();
        uint256 oldTotalShares = totalShares;

        for (uint8 i; i < 5; i++) {
            address payee = payees[i];
            uint256 share = shares[i];

            if (payee == _address) {
                if (share == _points) revert SameAllocation();
                uint256 oldShares = share;
                shares[i] = _points;
                totalShares = totalShares + _points - oldShares;
                break;
            } else if (payee != _address && share == 0 && !hasAllocation) {
                payees[i] = _address;
                shares[i] = _points;
                totalShares += _points;
                break;
            }
        }
        if (oldTotalShares == totalShares) revert SameAllocation();
    }

    /// @notice Update allocation rate for all payees
    /// @param _addresses Addresses for payees
    /// @param _points allocation points
    function updateAllocations(
        address[] memory _addresses,
        uint256[] memory _points
    ) external {
        if (_addresses.length != _points.length) revert DifferentInputLengths();
        if (_addresses.length > 10) revert MaxInputs();

        for (uint8 i; i < _addresses.length; i++) {
            updateAllocation(_addresses[i], _points[i]);
        }
    }

    /// @notice Split and send rewards among payees
    function splitProfits() public {
        uint256 sharesIncludingExecutor = totalShares + executorShare;
        uint256 amountTosplit = IERC20(antfarmToken).balanceOf(address(this));
        uint256 amount;

        for (uint8 i; i < 5; i++) {
            amount = (amountTosplit * shares[i]) / sharesIncludingExecutor;
            if (amount > 0) {
                TransferHelper.safeTransfer(antfarmToken, payees[i], amount);
            }
        }

        amount = (amountTosplit * executorShare) / sharesIncludingExecutor;
        TransferHelper.safeTransfer(antfarmToken, msg.sender, amount);
    }

    /// @notice Claim a specific DAO position rewards & split it among the payees
    /// @param _positionIds Position ID
    function claimAndSplitProfits(uint256[] memory _positionIds) external {
        IAntfarmPosition(antfarmPositions).claimDividendGrouped(_positionIds);
        splitProfits();
    }

    function withdrawPosition(uint256 _positionId) internal {
        IERC721Enumerable(antfarmPositions).transferFrom(
            address(this),
            msg.sender,
            _positionId
        );
    }

    /// @notice Transfer DAO positions to the governance contract
    /// @param _positionIds Positions ID
    function withdrawPositions(uint256[] memory _positionIds)
        external
        onlyOwner
    {
        for (uint8 i; i < _positionIds.length; i++) {
            withdrawPosition(_positionIds[i]);
        }
    }

    function onERC721Received(
        address, // operator,
        address, // from,
        uint256, // tokenId,
        bytes calldata // data
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
