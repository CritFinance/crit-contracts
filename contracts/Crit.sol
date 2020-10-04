// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CritSupplySchedule.sol";
import "./RewardsDistribution.sol";

contract Crit is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint;

    address public governance;
    address public supplySchedule;
    address public rewardsDistribution;
    address public rewardsOperation;

    modifier onlyGovernance {
        require(msg.sender == governance, "onlyGovernance");
        _;
    }

    constructor() public ERC20("Crit", "CRIT") {
        governance = msg.sender;
    }

    function setGovernance(address _governance) public onlyGovernance {
        require(_governance != address(0), "governance");
        governance = _governance;
    }

    function setSupplySchedule(address _supplySchedule) public onlyGovernance {
        require(_supplySchedule != address(0), "supplySchedule");
        supplySchedule = _supplySchedule;
    }

    function setRewardDistribution(address _distribution) public onlyGovernance {
        require(_distribution != address(0), "distribution");
        rewardsDistribution = _distribution;
    }

    function setRewardsOperation(address _operation) public onlyGovernance {
        require(_operation != address(0), "operation");
        rewardsOperation = _operation;
    }

    function mint() external {
        require(supplySchedule != address(0), "supplySchedule");
        require(rewardsDistribution != address(0), "rewardsDistribution");
        require(rewardsOperation != address(0), "rewardsOperation");

        CritSupplySchedule _supplySchedule = CritSupplySchedule(supplySchedule);
        RewardsDistribution _rewardsDistribution = RewardsDistribution(rewardsDistribution);

        uint supplyToMint = _supplySchedule.mintableSupply();
        require(supplyToMint > 0, "supplyToMint");

        _supplySchedule.recordMintEvent(supplyToMint);
        uint amountToOperate = _supplySchedule.rewardOfOperation(supplyToMint);
        uint amountToDistribute = supplyToMint.sub(amountToOperate);

        _mint(rewardsOperation, amountToOperate);
        _mint(rewardsDistribution, amountToDistribute);
        _rewardsDistribution.distributeRewards(amountToDistribute);
    }
}
