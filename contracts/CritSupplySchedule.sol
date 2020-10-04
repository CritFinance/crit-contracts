// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./SafeDecimal.sol";


contract CritSupplySchedule is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using SafeDecimal for uint;
    uint256[157] public weeklySupplies = [
    // week 0
    0,
    // 1st year, week 1 ~ 52
    358025, 250600, 175420, 122794, 112970, 103932, 95618, 87968, 80931, 74456, 68500, 63020, 57978,
    53340, 49073, 45147, 41535, 38212, 35155, 32343, 29755, 27375, 25185, 23170, 21316, 19611,
    18042, 16599, 15271, 14049, 12925, 11891, 10940, 10064, 9259, 8518, 7837, 7210, 6633,
    6102, 5614, 5165, 4752, 4372, 4022, 3700, 3404, 3132, 2881, 2651, 2438, 2244,
    // 2nd year, week 53 ~ 104
    2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244,
    2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244,
    2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244,
    2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244, 2244,
    // 3rd year, week 105 ~ 156
    1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734,
    1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734,
    1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734,
    1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734, 1734
    ];
    uint public constant MINT_PERIOD_DURATION = 1 weeks;
    uint public constant SUPPLY_START_DATE = 1601258400; // 2020-09-28T02:00:00+00:00

    uint public constant MAX_OPERATION_SHARES = 20e16;

    address public rewardsToken;
    uint public lastMintEvent;
    uint public weekCounter;
    uint public operationShares = 2e16; // 2%

    event OperationSharesUpdated(uint newShares);
    event SupplyMinted(uint supplyMinted, uint numberOfWeeksIssued, uint lastMintEvent, uint timestamp);

    modifier onlyRewardsToken() {
        require(msg.sender == address(rewardsToken), "onlyRewardsToken");
        _;
    }

    constructor(address _rewardsToken, uint _lastMintEvent, uint _currentWeek) public {
        rewardsToken = _rewardsToken;
        lastMintEvent = _lastMintEvent;
        weekCounter = _currentWeek;
    }

    function mintableSupply() external view returns (uint) {
        uint totalAmount;
        if (!isMintable()) {
            return 0;
        }

        uint currentWeek = weekCounter;
        uint remainingWeeksToMint = weeksSinceLastIssuance();
        while (remainingWeeksToMint > 0) {
            currentWeek++;
            remainingWeeksToMint--;
            if (currentWeek >= weeklySupplies.length) {
                break;
            }
            totalAmount = totalAmount.add(weeklySupplies[currentWeek]);
        }
        return totalAmount.mul(1e18);
    }

    function weeksSinceLastIssuance() public view returns (uint) {
        uint timeDiff = lastMintEvent > 0 ? now.sub(lastMintEvent) : now.sub(SUPPLY_START_DATE);
        return timeDiff.div(MINT_PERIOD_DURATION);
    }

    function isMintable() public view returns (bool) {
        if (now - lastMintEvent > MINT_PERIOD_DURATION && weekCounter < weeklySupplies.length) {
            return true;
        }
        return false;
    }

    function recordMintEvent(uint _supplyMinted) external onlyRewardsToken returns (bool) {
        uint numberOfWeeksIssued = weeksSinceLastIssuance();
        weekCounter = weekCounter.add(numberOfWeeksIssued);
        lastMintEvent = SUPPLY_START_DATE.add(weekCounter.mul(MINT_PERIOD_DURATION));

        emit SupplyMinted(_supplyMinted, numberOfWeeksIssued, lastMintEvent, now);
        return true;
    }

    function setOperationShares(uint _shares) external onlyOwner {
        require(_shares <= MAX_OPERATION_SHARES, "shares");
        operationShares = _shares;
        emit OperationSharesUpdated(_shares);
    }

    function rewardOfOperation(uint _supplyMinted) public view returns (uint) {
        return _supplyMinted.mul(operationShares).div(SafeDecimal.unit());
    }

    function currentWeekSupply() external view returns(uint) {
        if (weekCounter < weeklySupplies.length) {
            return weeklySupplies[weekCounter];
        }
        return 0;
    }
}
