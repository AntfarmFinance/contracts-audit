// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "../libraries/OwnableWithdrawable.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/math.sol";
import "../interfaces/IAntfarmToken.sol";
import "../interfaces/IPointsInterface.sol";

/// @title Antfarm Liquidity Mining
/// @notice A program that rewards Liquidy Providers that don't claim their ATF
contract AntfarmLiquidityMining is OwnableWithdrawable, Math {
    address public immutable antfarmToken;
    address public immutable governanceToken;

    uint256 public immutable startTime;
    uint256 public immutable rewardsAmount = 2_000_000 * 10**18;
    uint256 public immutable periodLength; // 4 weeks
    uint256 public immutable periods; // 39
    uint256 public immutable totalWeight;

    struct Rewards {
        uint256 points; // Square root of the ATF sum in Positions
        uint256 lastRegister;
    }

    mapping(address => Rewards) public rewards;
    mapping(uint256 => uint256) public totalPointsForPeriod;
    mapping(address => address) public pointsInterface;

    event Registered(
        address sender,
        uint256 period,
        uint256 amount,
        uint256 points
    );

    error AlreadyRegistered();
    error NoAction();

    constructor(
        address _antfarmToken,
        address _governanceToken,
        uint256 _periodLength,
        uint256 _periods,
        uint256 _startTime
    ) {
        require(_antfarmToken != address(0), "ZERO_ADDRESS");
        require(_governanceToken != address(0), "ZERO_ADDRESS");
        antfarmToken = _antfarmToken;
        governanceToken = _governanceToken;

        periodLength = _periodLength;
        periods = _periods;
        totalWeight = (_periods * (_periods + 1)) / 2;

        startTime = _startTime;
    }

    function setInterface(address _collection, address _interface)
        external
        onlyOwner
    {
        pointsInterface[_collection] = _interface;
    }

    function getClaimableAmounts(address _address)
        public
        view
        returns (uint256 amountATF, uint256 amountAGT)
    {
        Rewards memory reward = rewards[_address];

        amountAGT =
            (getPeriodReward(reward.lastRegister) * reward.points) /
            totalPointsForPeriod[reward.lastRegister];

        uint256 currentPeriod = getElapsedPeriods();
        uint256 amountToBurn;
        if (reward.lastRegister == currentPeriod - 1) {
            uint256 elapsedSeconds = (block.timestamp - startTime) %
                periodLength;

            uint256 slashingPeriod = (periodLength * 3) / 4;

            if (elapsedSeconds < slashingPeriod) {
                // Calculate the amount to be burned
                amountToBurn =
                    (amountAGT * (slashingPeriod - elapsedSeconds) * 50) /
                    (100 * slashingPeriod);
            }
        }
        amountATF = amountAGT - amountToBurn;
    }

    function sendRewards(address _address) internal {
        (uint256 amountATF, uint256 amountAGT) = getClaimableAmounts(_address);

        TransferHelper.safeTransfer(antfarmToken, _address, amountATF);
        TransferHelper.safeTransfer(governanceToken, _address, amountAGT);

        if (amountATF < amountAGT) {
            IAntfarmToken(antfarmToken).burn(amountAGT - amountATF);
        }
    }

    struct RegisterCollection {
        address collection;
        uint256[] ids;
    }

    function registerPositions(RegisterCollection[] calldata collections)
        external
    {
        Rewards memory reward = rewards[msg.sender];

        uint256 currentPeriod = getElapsedPeriods();
        if (reward.lastRegister == currentPeriod) revert AlreadyRegistered();

        bool sentRewards;
        if (reward.points > 0) {
            sentRewards = true;
            sendRewards(msg.sender);
        }

        uint256 rawPoints;
        uint256 collectionsLength = collections.length;

        for (uint256 i; i < collectionsLength; ++i) {
            rawPoints =
                rawPoints +
                IPointsInterface(pointsInterface[collections[i].collection])
                    .savePoints(currentPeriod, msg.sender, collections[i].ids);
        }

        if (rawPoints > 0) {
            uint256 points = sqrt(rawPoints);
            if (reward.lastRegister == currentPeriod - 1) {
                uint256 minPoints = min(reward.points, points);
                uint256 bonus = ((minPoints * 150) / 1000);
                points = points + bonus;
            }

            rewards[msg.sender] = Rewards(points, currentPeriod);
            emit Registered(msg.sender, currentPeriod, rawPoints, points);
            totalPointsForPeriod[currentPeriod] += points;
        } else {
            if (!sentRewards) revert NoAction();
            rewards[msg.sender] = Rewards(0, currentPeriod);
        }
    }

    function getElapsedPeriods()
        internal
        view
        returns (uint256 elapsedPeriods)
    {
        elapsedPeriods = (block.timestamp - startTime) / periodLength + 1;
    }

    function getPeriodReward(uint256 periodNumber)
        internal
        view
        returns (uint256 reward)
    {
        if (periodNumber > 0 && periodNumber < periods) {
            reward =
                (rewardsAmount * (periods + 1 - periodNumber)) /
                totalWeight;
        } else {
            reward = 0;
        }
    }

    struct PeriodDetails {
        uint256 lastPeriod;
        uint256 lastRewardsAmount;
        uint256 endTimestamp;
        uint256 permilleBurn;
        uint256 currentPeriod;
        uint256 currentRewardAmount;
    }

    function getPeriodDetails()
        external
        view
        returns (PeriodDetails memory periodDetails)
    {
        uint256 currentPeriod = getElapsedPeriods();
        uint256 lastPeriod = currentPeriod - 1;
        uint256 lastRewardsAmount = getPeriodReward(lastPeriod);
        uint256 endTimestamp = startTime + (periodLength * currentPeriod);

        uint256 elapsedSeconds = (block.timestamp - startTime) % periodLength;
        uint256 slashingPeriod = (periodLength * 3) / 4;
        uint256 permilleBurn;
        if (elapsedSeconds < slashingPeriod) {
            permilleBurn =
                ((slashingPeriod - elapsedSeconds) * 500) /
                slashingPeriod;
        } else {
            permilleBurn = 0;
        }

        uint256 currentRewardAmount = getPeriodReward(currentPeriod);

        periodDetails = PeriodDetails(
            lastPeriod,
            lastRewardsAmount,
            endTimestamp,
            permilleBurn,
            currentPeriod,
            currentRewardAmount
        );
    }

    struct UserDetails {
        uint256 lastPeriodParticipation;
        uint256 antfarmTokenToClaim;
        uint256 governanceTokenToClaim;
        uint256 maxRewardsCurrentPeriod;
    }

    function getUserDetails(
        address _address,
        RegisterCollection[] calldata collections
    ) external view returns (UserDetails memory userDetails) {
        uint256 currentPeriod = getElapsedPeriods();

        Rewards memory reward = rewards[_address];
        uint256 lastPeriodParticipation = reward.lastRegister;

        uint256 antfarmTokenToClaim;
        uint256 governanceTokenToClaim;
        if (
            lastPeriodParticipation > 0 &&
            lastPeriodParticipation != currentPeriod
        ) {
            (antfarmTokenToClaim, governanceTokenToClaim) = getClaimableAmounts(
                _address
            );
        } else {
            antfarmTokenToClaim = 0;
            governanceTokenToClaim = 0;
        }

        uint256 maxRewardsCurrentPeriod;
        if (lastPeriodParticipation == currentPeriod) {
            maxRewardsCurrentPeriod =
                (getPeriodReward(currentPeriod) * reward.points) /
                totalPointsForPeriod[currentPeriod];
        } else {
            uint256 rawPoints;
            uint256 collectionsLength = collections.length;

            for (uint256 i; i < collectionsLength; ++i) {
                rawPoints =
                    rawPoints +
                    IPointsInterface(pointsInterface[collections[i].collection])
                        .getPoints(
                            currentPeriod,
                            msg.sender,
                            collections[i].ids
                        );
            }

            if (rawPoints > 0) {
                uint256 points = sqrt(rawPoints);
                if (reward.lastRegister == currentPeriod - 1) {
                    uint256 minPoints = min(reward.points, points);
                    uint256 bonus = ((minPoints * 150) / 1000);
                    points = points + bonus;
                }
                uint256 totalPoints = totalPointsForPeriod[currentPeriod] +
                    points;
                maxRewardsCurrentPeriod =
                    (getPeriodReward(currentPeriod) * points) /
                    totalPoints;
            } else {
                maxRewardsCurrentPeriod = 0;
            }
        }

        userDetails = UserDetails(
            lastPeriodParticipation,
            antfarmTokenToClaim,
            governanceTokenToClaim,
            maxRewardsCurrentPeriod
        );
    }
}
