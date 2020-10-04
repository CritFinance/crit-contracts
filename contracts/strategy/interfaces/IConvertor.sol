// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IConvertor {
    function calc_withdraw_one_coin(uint256 _token_amount, int128 i) external view returns (uint256);
}