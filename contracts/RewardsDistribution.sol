/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/

* Docs: https://docs.synthetix.io/
*
*
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";


contract RewardsDistribution is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    address public rewardsToken;

    address[] public distributions;
    mapping(address => uint) public shares;

    event RewardDistributionAdded(uint index, address distribution, uint shares);
    event RewardDistributionUpdated(address distribution, uint shares);
    event RewardsDistributed(uint amount);

    modifier onlyRewardsToken() {
        require(msg.sender == address(rewardsToken) || msg.sender == owner(), "onlyRewardsToken");
        _;
    }

    constructor(address _rewardsToken) public {
        rewardsToken = _rewardsToken;
    }

    function addRewardDistribution(address _distribution, uint _shares) external onlyOwner {
        require(_distribution != address(0), "distribution");
        require(shares[_distribution] == 0, "shares");

        distributions.push(_distribution);
        shares[_distribution] = _shares;
        emit RewardDistributionAdded(distributions.length - 1, _distribution, _shares);
    }

    function updateRewardDistribution(address _distribution, uint _shares) public onlyOwner {
        require(_distribution != address(0), "distribution");
        require(_shares > 0, "shares");

        shares[_distribution] = _shares;
        emit RewardDistributionUpdated(_distribution, _shares);
    }

    function removeRewardDistribution(uint index) external onlyOwner {
        require(index <= distributions.length - 1, "index");

        delete shares[distributions[index]];
        delete distributions[index];
    }

    function distributeRewards(uint amount) external onlyRewardsToken returns (bool) {
        require(rewardsToken != address(0), "rewardsToken");
        require(amount > 0, "amount");
        require(IERC20(rewardsToken).balanceOf(address(this)) >= amount, "balance");

        uint remainder = amount;
        for (uint i = 0; i < distributions.length; i++) {
            address distribution = distributions[i];
            uint amountOfShares = sharesOf(distribution, amount);

            if (distribution != address(0) && amountOfShares != 0) {
                remainder = remainder.sub(amountOfShares);

                IERC20(rewardsToken).transfer(distribution, amountOfShares);
                bytes memory payload = abi.encodeWithSignature("notifyRewardAmount(uint256)", amountOfShares);
                distribution.call(payload);
            }
        }

        emit RewardsDistributed(amount);
        return true;
    }

    function totalShares() public view returns (uint) {
        uint total = 0;
        for (uint i = 0; i < distributions.length; i++) {
            total = total.add(shares[distributions[i]]);
        }
        return total;
    }

    function sharesOf(address _distribution, uint _amount) public view returns (uint) {
        uint _totalShares = totalShares();
        if (_totalShares == 0) return 0;

        return _amount.mul(shares[_distribution]).div(_totalShares);
    }
}
