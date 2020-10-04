// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IVault {
    function balance() external view returns (uint);
    function token() external view returns (address);
}
