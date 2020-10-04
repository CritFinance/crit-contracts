// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;


interface IReward {
    function rewardRate() external view returns(uint256);
    function rewardPerToken() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function stakingToken() external view returns(address);
    function earned(address account) external view returns (uint256);
}
