// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../interfaces/IERC20.sol";
import "../interfaces/IAntfarmStaking.sol";
import "../libraries/TransferHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AntfarmSale is Ownable {
    // Initial: just deployed, needs funds to be deposited to start Private
    // Private: any private investors can deposit ETH (vesting)
    // Public: any investor can deposit ETH
    // Success: sale reached the softcap
    // Cancel: sale didn't reach the softcap, anyone can withdraw
    // Final: if success, users can claim their ATF
    enum Status {
        Initial,
        Private,
        Public,
        Success,
        Cancel,
        Final
    }

    // Default value is the first element listed in
    // definition of the type, in this case "Initial"
    Status public status;

    address public immutable antfarmToken;
    address public stakingContract;

    uint256 public constant ATF_TO_SELL = 3 * 10**(6 + 18); // 3M Tokens to sell

    // Sale caps, Ether
    uint256 public immutable softcap;
    uint256 public immutable hardcap;
    uint256 public immutable privateCap;

    uint256 public totalPrivate;
    uint256 public totalPublic;

    // Rates, used in Final status to determine amounts bought
    uint256 public privateRate;
    uint256 public publicRate;

    uint256 public startTime;

    // Var states balances and whitelist
    mapping(address => uint256) public whitelist;
    mapping(address => uint256) public privateInvestedAmount;
    mapping(address => uint256) public privateSentAmount;
    mapping(address => uint256) public publicInvestedAmount;

    error IncorrectStatus();
    error MissingAntfarmTokens();
    error AmountNotAllowed();
    error SoftcapNotReached();
    error SoftcapReached();
    error CantCancelYet();
    error MissingStakingContract();

    constructor(
        address _antfarmToken,
        uint256 _softcap,
        uint256 _hardcap,
        uint256 _privateCap
    ) {
        require(_antfarmToken != address(0), "ZERO_ADDRESS");
        require(_softcap > 0 && _hardcap > 0 && _privateCap > 0, "CAPS_NULL");

        antfarmToken = _antfarmToken;
        softcap = _softcap;
        hardcap = _hardcap;
        privateCap = _privateCap;

        startTime = block.timestamp;
    }

    modifier isStatus(Status _status) {
        if (status != _status) revert IncorrectStatus();
        _;
    }

    function startPrivateSale() external onlyOwner isStatus(Status.Initial) {
        if (IERC20(antfarmToken).balanceOf(address(this)) < ATF_TO_SELL)
            revert MissingAntfarmTokens();

        status = Status.Private;
    }

    function setWhitelist(address _address, uint256 _amount)
        external
        onlyOwner
    {
        whitelist[_address] = _amount;
    }

    function investPrivate() external payable isStatus(Status.Private) {
        if (msg.value > whitelist[msg.sender]) revert AmountNotAllowed();
        if (msg.value + totalPrivate > privateCap) revert AmountNotAllowed();

        whitelist[msg.sender] -= msg.value;
        privateInvestedAmount[msg.sender] += msg.value;
        totalPrivate += msg.value;
    }

    function startPublicSale() external onlyOwner isStatus(Status.Private) {
        status = Status.Public;
    }

    function investPublic() external payable isStatus(Status.Public) {
        if (msg.value + totalPrivate + totalPublic >= hardcap)
            revert AmountNotAllowed();

        publicInvestedAmount[msg.sender] += msg.value;
        totalPublic += msg.value;
    }

    function setSuccess() external onlyOwner isStatus(Status.Public) {
        if (totalPrivate + totalPublic < softcap) revert SoftcapNotReached();
        status = Status.Success;
    }

    function setCancel() external onlyOwner isStatus(Status.Public) {
        if (totalPrivate + totalPublic > softcap) revert SoftcapReached();
        status = Status.Cancel;
    }

    function publicSetCancel() external isStatus(Status.Public) {
        if (totalPrivate + totalPublic > softcap) revert SoftcapReached();
        if (startTime + 4 weeks > block.timestamp) revert CantCancelYet();
        status = Status.Cancel;
    }

    function publicSetCancelFromPrivate() external isStatus(Status.Private) {
        if (totalPrivate + totalPublic > softcap) revert SoftcapReached();
        if (startTime + 5 weeks > block.timestamp) revert CantCancelYet();
        status = Status.Cancel;
    }

    function claimEther() external onlyOwner isStatus(Status.Success) {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function setFinal() external onlyOwner isStatus(Status.Success) {
        uint256 totalRaised = ((totalPrivate * 125) / 100) + totalPublic;
        privateRate = (ATF_TO_SELL * 1250) / totalRaised; // improve ratio precision
        publicRate = (ATF_TO_SELL * 1000) / totalRaised; // improve ratio precision
        status = Status.Final;

        // Initialise vesting period
        startTime = block.timestamp;
    }

    function claimTokensPublic() external isStatus(Status.Final) {
        uint256 amount = publicInvestedAmount[msg.sender];
        publicInvestedAmount[msg.sender] = 0;
        TransferHelper.safeTransfer(
            antfarmToken,
            msg.sender,
            (amount * publicRate) / 1000
        );
    }

    function claimTokensPrivate() public isStatus(Status.Final) {
        uint256 unvested = _calculateUnvested();

        uint256 claimable = unvested - privateSentAmount[msg.sender];

        privateSentAmount[msg.sender] = unvested;
        TransferHelper.safeTransfer(
            antfarmToken,
            msg.sender,
            (claimable * privateRate) / 1000
        );
    }

    function setStakingContract(address _stakingContract) external onlyOwner {
        stakingContract = _stakingContract;
    }

    function stakeTokensPrivate() external isStatus(Status.Final) {
        if (stakingContract == address(0)) revert MissingStakingContract();

        claimTokensPrivate();

        uint256 remainingVested = privateInvestedAmount[msg.sender] -
            privateSentAmount[msg.sender];

        privateSentAmount[msg.sender] = privateInvestedAmount[msg.sender];
        uint256 antfarmAmount = (remainingVested * privateRate) / 1000;
        IERC20(antfarmToken).approve(stakingContract, antfarmAmount);
        IAntfarmStaking(stakingContract).depositVested(
            msg.sender,
            antfarmAmount
        );
    }

    function _calculateUnvested() internal view returns (uint256 unvested) {
        uint256 elapsedTime = block.timestamp - startTime;

        if (elapsedTime > 78 weeks) {
            elapsedTime = 78 weeks;
        }

        unvested = (privateInvestedAmount[msg.sender] * elapsedTime) / 78 weeks;
    }

    fallback() external payable {
        revert();
    }
}
