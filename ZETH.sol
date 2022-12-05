// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ZETH is IERC20 {
    string public name     = "Wrapped Ether By Z Custody";
    string public symbol   = "ZETH";
    uint8  public decimals = 18;

    mapping (address => uint) private _balances;
    mapping (address => mapping (address => uint)) private _allowances;

    event Deposit(address indexed adr, uint amount);
    event Withdrawal(address indexed adr, uint amount);

    constructor() {}

    receive() external payable {
        _balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function totalSupply() external view returns (uint256) {
        return address(this).balance;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return transferFrom(msg.sender, to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        require(_balances[from] >= amount, "Not enough to transfer out");

        if (from != msg.sender) {
            require(_allowances[from][msg.sender] >= amount, "Allowance not enough for transfer out");
            _allowances[from][msg.sender] -= amount;
        }

        _balances[from] -= amount;
        _balances[to] += amount;

        emit Transfer(from, to, amount);

        return true;
    }

    function withdraw(uint amount) public {
        require(_balances[msg.sender] >= amount, "Not enough to withdraw");
        _balances[msg.sender] -= amount;
        (bool success, ) =  msg.sender.call{value: amount}("");
        require(success, "withdraw issue!");
        emit Withdrawal(msg.sender, amount);
    }
}