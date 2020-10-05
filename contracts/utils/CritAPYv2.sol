// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/Vault.sol";
import "../strategy/interfaces/IConvertor.sol";
import "./interfaces/IReward.sol";
import "../library/UniswapPriceOracle.sol";
import "../interfaces/ICritAPY.sol";

contract CritAPYv2 {
    using UniswapPriceOracle for address;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IConvertor public zap = IConvertor(0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3);

    address public constant CRIT = 0xf00eA2f3761a730f414aeE6DfDC7857b6a3Ef086;
    ICritAPY public constant APYv1 = ICritAPY(0xA35f8ed4156a13a7696c61D4d73791091CB77308);

    constructor() public {
    }

    function getYCrvAPY() public view returns (uint256) {
        return APYv1.getYCrvAPY();
    }

    function calculateAPYByVault(address vault) external view returns (uint256) {
        return APYv1.calculateAPYByVault(vault);
    }

    function calculateAPYByReward(address _reward) external view returns(uint256) {
        IReward reward = IReward(_reward);
        address cToken = reward.stakingToken();
        address token = Vault(cToken).token();
        uint tokenDecimals = 10**uint256(ERC20(token).decimals());
        uint totalSupply = reward.totalSupply();
        if (totalSupply == 0) {
            totalSupply = tokenDecimals;
        }

        uint rewardPerTokenPerSecond = reward.rewardRate() * tokenDecimals / totalSupply;
        uint tokenPrice;
        if (token == WETH) {
            tokenPrice = 1e18;
        } else {
            tokenPrice = token.perETH();
        }
        uint critPrice = CRIT.perETH();
        uint apy = 100 * rewardPerTokenPerSecond * (365 days) * critPrice / tokenPrice;
        return apy;
    }
}