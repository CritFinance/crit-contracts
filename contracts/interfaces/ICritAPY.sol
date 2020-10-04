// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface ICritAPY {
    function logHarvest(uint _totalSupply, uint _profit) external;
}