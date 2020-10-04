// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/Controller.sol";

contract CritVault is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;

    uint public min = 9500;
    uint public constant max = 10000;

    address public governance;
    address public controller;

    mapping (address => uint256) public depositedAt;
    uint public feeFreeDepositTime = 3 days;
    uint public withdrawalFee = 50;

    modifier onlyGovernance {
        require(msg.sender == governance, "!governance");
        _;
    }

    constructor (address _token, address _controller) public ERC20(
        string(abi.encodePacked("Crit ", ERC20(_token).name())),
        string(abi.encodePacked("c", ERC20(_token).symbol()))
    ) {
        _setupDecimals(ERC20(_token).decimals());
        token = IERC20(_token);
        governance = msg.sender;
        controller = _controller;
    }

    function balance() public view returns (uint) {
        return token.balanceOf(address(this))
        .add(Controller(controller).balanceOf(address(this)));
    }

    function setMin(uint _min) external onlyGovernance {
        min = _min;
    }

    function setGovernance(address _governance) external onlyGovernance {
        governance = _governance;
    }

    function setController(address _controller) external onlyGovernance {
        controller = _controller;
    }

    function setFeeFreeDepositTime(uint _time) external onlyGovernance {
        feeFreeDepositTime = _time;
    }

    function setWithdrawalFee(uint _fee) external onlyGovernance {
        require(_fee < max, 'wrong fee');
        withdrawalFee = _fee;
    }

    // Custom logic in here for how much the vault allows to be borrowed
    // Sets minimum required on-hand to keep small withdrawals cheap
    function available() public view returns (uint) {
        return token.balanceOf(address(this)).mul(min).div(max);
    }

    function earn() public {
        uint _bal = available();
        token.safeTransfer(controller, _bal);
        Controller(controller).earn(address(this), _bal);
    }

    function depositAll() external {
        deposit(token.balanceOf(msg.sender));
    }

    function deposit(uint _amount) public {
        uint _pool = balance();
        uint _before = token.balanceOf(address(this));
        depositedAt[msg.sender] = block.timestamp;
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint _after = token.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }


    // Used to swap any borrowed reserve over the debt limit to liquidate to 'token'
    function harvest(address reserve, uint amount) external {
        require(msg.sender == controller, "!controller");
        require(reserve != address(token), "token");
        IERC20(reserve).safeTransfer(controller, amount);
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint _shares) public {
        uint r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        // Check balance
        uint b = token.balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r.sub(b);
            Controller(controller).withdraw(address(this), _withdraw);
            uint _after = token.balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        uint fee = 0;
        if (!isFeeFree(msg.sender)) {
            fee = r.mul(withdrawalFee).div(max);
            token.safeTransfer(Controller(controller).rewards(), fee);
        }

        token.safeTransfer(msg.sender, r.sub(fee));
    }

    function isFeeFree(address account) public view returns (bool) {
        return depositedAt[account] + feeFreeDepositTime <= block.timestamp;
    }

    function getPricePerFullShare() public view returns (uint) {
        return balance().mul(1e18).div(totalSupply());
    }
}