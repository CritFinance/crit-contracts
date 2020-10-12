// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface ICritAMMSignal {
    enum Signal {
        idle, buy, sell
    }

    function getSignal() external view returns(Signal signal, uint256 amount);
}