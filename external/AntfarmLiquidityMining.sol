// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../interfaces/IERC20.sol";
import "../interfaces/IAntfarmPosition.sol";
import "../libraries/TransferHelper.sol";
import "../utils/AntfarmLiquidityMiningErrors.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AntfarmLiquidityMining is Ownable {
    address public immutable antfarmPositions;
    address public immutable antfarmToken;
    address public immutable antfarmGovernanceToken;

    uint32 public immutable startTime;
    uint32 public immutable endTime;
    uint32 public constant START_RATE = 100;
    uint32 public constant END_RATE = 30;
    uint128 public constant INITIAL_RESERVE = 2 * 10**6 * 10**18;

    mapping(uint256 => uint256) public lastBonusClaim;
    mapping(address => bool) public pairWhitelist;

    event BonusClaimed(
        uint256 positionId,
        uint256 bonusAmount,
        uint256 governanceAmount
    );

    constructor(
        address _antfarmPositions,
        address _antfarmToken,
        address _antfarmGovernanceToken
    ) {
        require(_antfarmPositions != address(0), "ZERO_ADDRESS");
        require(_antfarmToken != address(0), "ZERO_ADDRESS");
        require(_antfarmGovernanceToken != address(0), "ZERO_ADDRESS");
        antfarmPositions = _antfarmPositions;
        antfarmToken = _antfarmToken;
        antfarmGovernanceToken = _antfarmGovernanceToken;
        startTime = uint32(block.timestamp);
        endTime = startTime + 94608000; // 3 years in seconds
    }

    modifier inTime() {
        if (block.timestamp < startTime || block.timestamp > endTime) {
            revert OutOfTimeWindow();
        }
        _;
    }

    function claimBonusGrouped(uint256[] calldata positionIds) external inTime {
        IAntfarmPosition positionsContract = IAntfarmPosition(antfarmPositions);

        uint256 totalBonus;
        uint256 totalGovernance;

        for (uint256 i; i < positionIds.length; i++) {
            IAntfarmPosition.PositionDetails memory position = positionsContract
                .getPositionDetails(positionIds[i]);

            ensurePositionCanClaim(position);

            if (position.dividend == 0) revert NothingToClaim();

            lastBonusClaim[positionIds[i]] = block.timestamp;

            (uint256 bonusAmount, uint256 governanceAmount) = getBonusAmount(
                positionIds[i]
            );
            totalBonus += bonusAmount;
            totalGovernance += governanceAmount;

            emit BonusClaimed(positionIds[i], bonusAmount, governanceAmount);
        }

        if (totalBonus + totalGovernance == 0) revert NothingToClaim();
        TransferHelper.safeTransfer(antfarmToken, msg.sender, totalBonus);
        TransferHelper.safeTransfer(
            antfarmGovernanceToken,
            msg.sender,
            totalGovernance
        );
    }

    function claimBonus(uint256 positionId) external inTime {
        // Get the position
        IAntfarmPosition positionsContract = IAntfarmPosition(antfarmPositions);
        IAntfarmPosition.PositionDetails memory position = positionsContract
            .getPositionDetails(positionId);

        ensurePositionCanClaim(position);

        // Register last claim
        lastBonusClaim[positionId] = block.timestamp;
        if (position.dividend == 0) revert NothingToClaim();

        // Calculate bonus and governance amounts to send
        (uint256 bonusAmount, uint256 governanceAmount) = getBonusAmount(
            position.dividend
        );
        if (bonusAmount + governanceAmount == 0) revert NothingToClaim();

        // Send the bonus to the user if any
        if (bonusAmount > 0) {
            TransferHelper.safeTransfer(antfarmToken, msg.sender, bonusAmount);
        }

        // Send governance amount if any
        if (governanceAmount > 0) {
            TransferHelper.safeTransfer(
                antfarmGovernanceToken,
                msg.sender,
                governanceAmount
            );
        }
        emit BonusClaimed(positionId, bonusAmount, governanceAmount);
    }

    function whitelist(address[] memory pairs) external onlyOwner {
        for (uint256 i; i < pairs.length; i++) {
            pairWhitelist[pairs[i]] = true;
        }
    }

    function unwhitelist(address[] memory pairs) external onlyOwner {
        for (uint256 i; i < pairs.length; i++) {
            pairWhitelist[pairs[i]] = false;
        }
    }

    function withdrawToken(address _token, uint256 _amount) external onlyOwner {
        TransferHelper.safeTransfer(_token, owner(), _amount);
    }

    function withdrawTotalTokenBalance(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        TransferHelper.safeTransfer(_token, owner(), amount);
    }

    function getBonusAmount(uint256 dividendAmount)
        public
        view
        returns (uint256 bonusAmount, uint256 governanceAmount)
    {
        uint256 timeAmount = getBonusRateFromTime(dividendAmount);
        uint256 reserveBonusAmount = getAmountRateFromReserve(
            dividendAmount,
            antfarmToken
        );
        bonusAmount = timeAmount < reserveBonusAmount
            ? timeAmount
            : reserveBonusAmount;

        uint256 reserveGovernanceAmount = getAmountRateFromReserve(
            dividendAmount,
            antfarmGovernanceToken
        );
        governanceAmount = timeAmount < reserveGovernanceAmount
            ? timeAmount
            : reserveGovernanceAmount;
    }

    function getBonusRateFromTime(uint256 dividendAmount)
        internal
        view
        returns (uint256 bonusAmount)
    {
        uint256 maxBonus = (dividendAmount * START_RATE) / 1000;
        uint256 minBonus = (dividendAmount * END_RATE) / 1000;
        uint256 timeElapsed = (1000 * (block.timestamp - startTime)) /
            (endTime - startTime);

        bonusAmount = (timeElapsed *
            minBonus +
            maxBonus -
            (timeElapsed * maxBonus));
    }

    function getAmountRateFromReserve(
        uint256 dividendAmount,
        address tokenAddress
    ) internal view returns (uint256 bonusAmount) {
        uint256 maxBonus = (dividendAmount * START_RATE) / 1000;
        uint256 minBonus = (dividendAmount * END_RATE) / 1000;
        uint256 reserve = IERC20(tokenAddress).balanceOf(address(this));
        uint256 reservePercentage = (1000 * reserve) / INITIAL_RESERVE;

        bonusAmount =
            ((reservePercentage * (maxBonus - minBonus)) / 1000) +
            minBonus;
    }

    function ensurePositionCanClaim(
        IAntfarmPosition.PositionDetails memory position
    ) internal view {
        // Verify if the sender is the owner
        if (msg.sender != position.owner) revert NotOwner();

        // Verify the pair is whitelisted
        if (!pairWhitelist[position.pair]) revert PairNotWhitelisted();

        // Verify it hasn't claimed in the last 28 days
        if (lastBonusClaim[position.id] > block.timestamp - (28 * 86400)) {
            revert AlreadyClaimed();
        }
    }
}
