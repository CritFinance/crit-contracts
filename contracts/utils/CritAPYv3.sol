// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/Vault.sol";
import "../strategy/interfaces/IConvertor.sol";
import "./interfaces/IReward.sol";
import "../library/UniswapPriceOracle.sol";
import "../interfaces/ICritAPY.sol";
import "../../interfaces/Strategy.sol";

contract CritAPYv3 {
    using UniswapPriceOracle for address;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    IConvertor private zap = IConvertor(0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3);

    address private constant CRIT = 0xf00eA2f3761a730f414aeE6DfDC7857b6a3Ef086;
    address private constant strategyCurveYCRV = 0x1e7d5ECEB33c12Fc9E920D7d3179e1C4396fd2e4;
    address private constant CRIT_ETH_UNI_LP = 0x56ebF3ec044043efbcC13D66E46cc30bD0D35fD2;

    struct APYData {
        uint totalSupply;
        uint profit;
        uint64 timeInvested;
        uint64 timestamp;
    }

    mapping (address => APYData) public latestData;
    event Harvest(address strategy, uint totalSupply, uint profit, uint timeInvested, uint timestamp);

    constructor() public {
    }

    function logHarvest(uint _totalSupply, uint _profit) external {
        APYData storage data = latestData[msg.sender];
        if (data.timestamp == 0) {
            data.totalSupply = _totalSupply;
            data.profit = _profit;
            data.timeInvested = 0;
            data.timestamp = uint64(block.timestamp);
            return;
        }

        uint timeInvested = block.timestamp - data.timestamp;
        data.timeInvested = uint64(timeInvested);
        data.timestamp = uint64(block.timestamp);
        data.totalSupply = _totalSupply;
        data.profit = _profit;
        emit Harvest(msg.sender, _totalSupply, _profit, timeInvested, block.timestamp);
    }

    function getYCrvAPY() public view returns (uint256) {
        APYData memory data = latestData[strategyCurveYCRV];
        Strategy strategy = Strategy(strategyCurveYCRV);
        uint value = strategy.want().daiValue(data.totalSupply);
        uint profit = data.profit;
        uint apy = 100 * profit * 1e18 / value * 365 days / data.timeInvested;

        return apy;
    }

    function calculateAPYByVault(address vault) external view returns (uint256) {
        address token = address(Vault(vault).token());
        if (token == DAI) {
            return getYCrvAPY() * 1e18 / zap.calc_withdraw_one_coin(1e18, 0);
        } else if(token == USDC) {
            return getYCrvAPY() * 1e6 / zap.calc_withdraw_one_coin(1e18, 1);
        } else if(token == USDT) {
            return getYCrvAPY() * 1e6 / zap.calc_withdraw_one_coin(1e18, 2);
        } else {
            return 0;
        }
    }

    function calculateAPYByReward(address _reward) external view returns(uint256) {
        IReward reward = IReward(_reward);
        address cToken = reward.stakingToken();
        address token;
        if (cToken == CRIT_ETH_UNI_LP) {
            token = CRIT_ETH_UNI_LP;
        } else {
            token = Vault(cToken).token();
        }

        uint tokenDecimals = 10**uint256(ERC20(token).decimals());
        uint totalSupply = reward.totalSupply();
        if (totalSupply == 0) {
            totalSupply = tokenDecimals;
        }

        uint rewardPerTokenPerSecond = reward.rewardRate() * tokenDecimals / totalSupply;
        uint tokenPrice;
        if (token == WETH) {
            tokenPrice = 1e18;
        } else if (token == CRIT_ETH_UNI_LP) {
            tokenPrice = IERC20(WETH).balanceOf(CRIT_ETH_UNI_LP) * 2e18 / IERC20(CRIT_ETH_UNI_LP).totalSupply();
        } else {
            tokenPrice = token.perETH();
        }
        uint critPrice = CRIT.perETH();
        uint apy = 100 * rewardPerTokenPerSecond * (365 days) * critPrice / tokenPrice;
        return apy;
    }
}