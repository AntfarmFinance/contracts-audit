// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "../libraries/OwnableWithdrawable.sol";
import "../libraries/TransferHelper.sol";

contract AntfarmSale is OwnableWithdrawable {
    // Initial: just deployed, owner needs to start public sale
    // Public: any investor can deposit ETH
    // Success: sale reached the softcap, owner can withdraw ETH deposited
    // Cancel: sale didn't reach the softcap, anyone can withdraw
    // Final: if success, users can claim their ATF
    enum Status {
        Initial,
        Public,
        Success,
        Cancel,
        Final
    }

    // Default value is the first element listed in
    // definition of the type, in this case "Initial"
    Status public status;

    address public immutable antfarmToken;

    uint256 public constant ATF_TO_SELL = 3_000_000 * 10**18;

    // Sale caps, Ether
    uint256 public immutable softcap;
    uint256 public immutable hardcap;

    uint256 public totalAmount;

    uint256 public startTime;

    // Var states balances and whitelist
    mapping(address => uint256) public investedAmount;

    error IncorrectStatus();
    error AmountNotAllowed();
    error SoftcapNotReached();
    error SoftcapReached();
    error CantCancelYet();

    constructor(
        address _antfarmToken,
        uint256 _softcap,
        uint256 _hardcap
    ) {
        require(_antfarmToken != address(0), "ZERO_ADDRESS");
        require(_softcap > 0 && _hardcap > 0, "CAPS_NULL");

        antfarmToken = _antfarmToken;
        softcap = _softcap;
        hardcap = _hardcap;

        startTime = block.timestamp;
    }

    modifier isStatus(Status _status) {
        if (status != _status) revert IncorrectStatus();
        _;
    }

    function startPublicSale() external onlyOwner isStatus(Status.Initial) {
        status = Status.Public;
    }

    function investPublic() external payable isStatus(Status.Public) {
        if (msg.value + totalAmount >= hardcap) revert AmountNotAllowed();

        investedAmount[msg.sender] += msg.value;
        totalAmount += msg.value;
    }

    function setSuccess() external onlyOwner isStatus(Status.Public) {
        if (totalAmount < softcap) revert SoftcapNotReached();
        status = Status.Success;
    }

    function setCancel() external onlyOwner isStatus(Status.Public) {
        if (totalAmount > softcap) revert SoftcapReached();
        status = Status.Cancel;
    }

    function publicSetCancel() external isStatus(Status.Public) {
        if (totalAmount > softcap) revert SoftcapReached();
        if (startTime + 4 weeks > block.timestamp) revert CantCancelYet();
        status = Status.Cancel;
    }

    function withdrawEth() external isStatus(Status.Cancel) {
        uint256 amountInvested = investedAmount[msg.sender];
        investedAmount[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amountInvested}("");
        require(success, "Transfer failed.");
    }

    function claimEther() external onlyOwner isStatus(Status.Success) {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function setFinal() external onlyOwner isStatus(Status.Success) {
        status = Status.Final;
    }

    function claimTokens() external isStatus(Status.Final) {
        uint256 amount = investedAmount[msg.sender];
        investedAmount[msg.sender] = 0;
        TransferHelper.safeTransfer(
            antfarmToken,
            msg.sender,
            (ATF_TO_SELL * amount) / totalAmount
        );
    }

    fallback() external payable {
        revert();
    }
}
