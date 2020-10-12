// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/Controller.sol";

contract CritVaultLocked is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;

    uint public min = 9500;
    uint public constant max = 10000;

    address public governance;
    address public controller;

    mapping (address => uint256) public depositedAt;
    uint public lockingDuration = 7 days;

    modifier onlyGovernance {
        require(msg.sender == governance, "!governance");
        _;
    }

    constructor (address _token, address _controller) public ERC20(
        string(abi.encodePacked("c", ERC20(_token).name())),
        string(abi.encodePacked("c", ERC20(_token).symbol()))
    ) {
        _setupDecimals(ERC20(_token).decimals());
        token = IERC20(_token);
        governance = msg.sender;
        controller = _controller;
    }

    function balance() public view returns (uint) {
        return totalSupply();
    }

    function setMin(uint _min) external onlyGovernance {
        min = _min;
    }

    function setGovernance(address _governance) external onlyGovernance {
        require(_governance != address(0), "0x0");
        governance = _governance;
    }

    function setController(address _controller) external onlyGovernance {
        require(_controller != address(0), "0x0");
        controller = _controller;
    }

    function setLockingDuration(uint _time) external onlyGovernance {
        lockingDuration = _time;
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
        uint _before = token.balanceOf(address(this));
        depositedAt[msg.sender] = block.timestamp;
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint _after = token.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        _mint(msg.sender, _amount);
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
        require(isLocked(msg.sender) == false, "locked");

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

        token.safeTransfer(msg.sender, r);
    }

    function isLocked(address account) public view returns (bool) {
        return depositedAt[account] + lockingDuration >= block.timestamp;
    }

    function getPricePerFullShare() public pure returns (uint) {
        return 1e18;
    }
}