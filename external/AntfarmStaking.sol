// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Antfarm Staking
/// @author Antfarm team
/// @notice Allows holders of ATF to stake ATF in order to receive AGT rewards
contract AntfarmStaking {
    using SafeERC20 for IERC20;
    address public antfarmToken;
    address public governanceToken;

    struct Reward {
        uint256 reward;
        uint256 lastRewardPoints;
    }

    uint256 public constant INITIAL_RESERVE = 2 * 10**(6 + 18); // 2M tokens
    uint256 public immutable startTime;
    uint256 public lastAmount = 0;
    uint256 private constant MONTH = 2629743;

    uint256 private totalSupply = 0;
    uint256 private totalRewardPoints = 0;
    uint256 private unclaimedRewards = 0;
    uint256 private constant POINT_MULTIPLIER = 1 ether;
    mapping(address => Reward) public rewards;
    mapping(address => uint256) public balanceOf;

    mapping(address => uint256) public totalVestedAmount;
    mapping(address => uint256) public unvestedAmount;

    event Deposit(address sender, uint256 amount, uint256 timestamp);
    event DepositVested(address sender, uint256 amount, uint256 timestamp);
    event Withdraw(address receiver, uint256 amount, uint256 timestamp);
    event WithdrawVested(address receiver, uint256 amount, uint256 timestamp);

    error NullAmount();
    error AmountTooHigh();
    error NothingToClaim();

    constructor(
        address _antfarmToken,
        address _governanceToken,
        uint256 _startTime
    ) {
        require(_antfarmToken != address(0), "NULL_ATF_ADDRESS");
        require(_governanceToken != address(0), "NULL_AGT_ADDRESS");
        require(
            _startTime >= block.timestamp &&
                _startTime <= block.timestamp + MONTH,
            "INCORRECT_START_TIME"
        );
        antfarmToken = _antfarmToken;
        governanceToken = _governanceToken;
        startTime = _startTime;
    }

    modifier disburse() {
        uint256 amount = getAmountToRelease(block.timestamp) - lastAmount;

        if (amount > 0 && totalSupply > 0) {
            totalRewardPoints += (amount * POINT_MULTIPLIER) / totalSupply;
            unclaimedRewards += amount;
            lastAmount = amount;
        }

        _;
    }

    modifier updateRewards(address _address) {
        uint256 owing = newRewards(_address, totalRewardPoints);
        if (owing > 0) {
            unclaimedRewards -= owing;
            rewards[_address].reward += owing;
        }

        rewards[_address].lastRewardPoints = totalRewardPoints;

        _;
    }

    /// @notice Deposit `_amount` tokens for `msg.sender`
    /// @param _amount ATF amount to deposit
    function deposit(uint256 _amount)
        external
        disburse
        updateRewards(msg.sender)
    {
        if (_amount == 0) revert NullAmount();
        balanceOf[msg.sender] += _amount;
        totalSupply += _amount;

        emit Deposit(msg.sender, _amount, block.timestamp);

        IERC20(antfarmToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
    }

    function depositVested(address _for, uint256 _amount)
        external
        disburse
        updateRewards(_for)
    {
        if (_amount == 0) revert NullAmount();
        totalVestedAmount[_for] += _amount;
        totalSupply += _amount;
        emit DepositVested(_for, _amount, block.timestamp);

        IERC20(antfarmToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
    }

    /// @notice Withdraw all available ATF vested tokens for `msg.sender`
    function withdrawVested() external disburse updateRewards(msg.sender) {
        uint256 amount = _calculateUnvested() - unvestedAmount[msg.sender];

        if (amount == 0) revert NullAmount();
        _withdrawVested(amount);
    }

    /// @notice Withdraw a specific amount ATF vested tokens for `msg.sender`
    function withdrawVested(uint256 _amount)
        external
        disburse
        updateRewards(msg.sender)
    {
        uint256 maxAmount = _calculateUnvested() - unvestedAmount[msg.sender];
        if (_amount > maxAmount) revert AmountTooHigh();
        _withdrawVested(_amount);
    }

    function _calculateUnvested() internal view returns (uint256 unvested) {
        uint256 elapsedTime = block.timestamp - startTime;

        if (elapsedTime > 78 weeks) {
            elapsedTime = 78 weeks;
        }

        unvested = (totalVestedAmount[msg.sender] * elapsedTime) / 78 weeks;
    }

    function _withdrawVested(uint256 _amount) internal {
        unvestedAmount[msg.sender] += _amount;
        totalSupply -= _amount;
        emit WithdrawVested(msg.sender, _amount, block.timestamp);
        IERC20(antfarmToken).safeTransfer(msg.sender, _amount);
    }

    function vestedBalanceOf(address _address)
        external
        view
        returns (uint256 balance)
    {
        balance = totalVestedAmount[_address] - unvestedAmount[_address];
    }

    /// @notice Withdraw all ATF tokens for `msg.sender`
    /// He can later claim his AGT is any in pending rewards
    function withdraw() external disburse updateRewards(msg.sender) {
        uint256 amount = balanceOf[msg.sender];
        if (amount == 0) revert NullAmount();
        _withdraw(amount);
    }

    /// @notice Withdraw a specific amount of tokens for `msg.sender`
    /// He can later claim his AGT is any in pending rewards
    function withdraw(uint256 _amount)
        external
        disburse
        updateRewards(msg.sender)
    {
        if (_amount > balanceOf[msg.sender]) revert AmountTooHigh();
        if (_amount == 0) revert NullAmount();
        _withdraw(_amount);
    }

    function _withdraw(uint256 _amount) internal {
        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;
        emit Withdraw(msg.sender, _amount, block.timestamp);
        IERC20(antfarmToken).safeTransfer(msg.sender, _amount);
    }

    /// @notice Get the amout of rewards claimable after a disburse
    /// @param _address Address to claim
    /// @return amount Claimable AGT amount
    function claimableRewards(address _address)
        external
        view
        returns (uint256 amount)
    {
        uint256 temptotalRewardPoints = totalRewardPoints;

        // Recalculate total reward points
        uint256 newAmount = getAmountToRelease(block.timestamp) - lastAmount;

        if (newAmount > 0) {
            temptotalRewardPoints +=
                (newAmount * POINT_MULTIPLIER) /
                totalSupply;
        }

        uint256 newReward = newRewards(_address, temptotalRewardPoints);
        amount = rewards[_address].reward + newReward;
    }

    /// @notice Claim AGT staking rewards for `msg.sender`
    function claimStakingRewards() external disburse updateRewards(msg.sender) {
        uint256 claimAmount = rewards[msg.sender].reward;

        if (claimAmount == 0) revert NullAmount();

        rewards[msg.sender].reward = 0;
        IERC20(governanceToken).safeTransfer(msg.sender, claimAmount);
    }

    /// @notice Calculates the amount owed on top of Reward.reward
    /// @param _address Calculate amount for
    /// @param _totalRewardPoints Total reward points, useful to calulate without previous disburse
    function newRewards(address _address, uint256 _totalRewardPoints)
        internal
        view
        returns (uint256 amount)
    {
        uint256 newRewardPoints = _totalRewardPoints -
            rewards[_address].lastRewardPoints;
        uint256 stakedBalance = balanceOf[_address] +
            totalVestedAmount[_address] -
            unvestedAmount[_address];
        amount = (stakedBalance * newRewardPoints) / POINT_MULTIPLIER;
    }

    function getAmountToRelease(uint256 _timestamp)
        public
        view
        returns (uint256)
    {
        // Return 0 while the staking period hasn't started
        if (_timestamp < startTime) {
            return 0;
        }

        // Full months elapsed
        uint256 elapsedMonths = (_timestamp - startTime) / MONTH;

        // Return total amount after 12 completed months
        if (elapsedMonths > 11) {
            return INITIAL_RESERVE;
        }

        // Elapsed time in last month
        uint256 elapsedSeconds = (_timestamp - startTime) % MONTH;
        uint256 currentMonthWeight = 12 - elapsedMonths;

        uint256 currentMonthAmount = (currentMonthWeight *
            elapsedSeconds *
            INITIAL_RESERVE) / (78 * MONTH);

        // Return only first month
        if (elapsedMonths == 0) {
            return currentMonthAmount;
        }

        // Calculate amount for past periods
        uint256 weight = 6 *
            13 -
            (((12 - elapsedMonths) * (13 - elapsedMonths)) / 2);
        uint256 monthsAmount = (weight * INITIAL_RESERVE) / 78;

        return monthsAmount + currentMonthAmount;
    }
}
