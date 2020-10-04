// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IUniswapV2Router02.sol";
import "../CritVault.sol";
import "../../interfaces/Strategy.sol";
import "../strategy/interfaces/IConvertor.sol";
import "./interfaces/IReward.sol";

import "../library/UniswapPriceOracle.sol";


contract CritAPY is Ownable {
    using UniswapPriceOracle for address;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    IConvertor public zap = IConvertor(0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3);

    struct APYData {
        uint timeInvested;
        uint totalSupply;
        uint profit;
    }

    mapping (address => APYData) public latestData;

    address public crit;
    address public strategyCurveYCRV;

    event Harvest(address strategy, uint timeInvested, uint totalSupply, uint profit);

    constructor(address _crit) public {
        crit = _crit;
    }

    function setStrategyCurveYCRV(address _strategy) external onlyOwner {
        strategyCurveYCRV = _strategy;
    }

    function getYCrvAPY() public view returns (uint256) {
        APYData memory data = latestData[strategyCurveYCRV];
        Strategy strategy = Strategy(strategyCurveYCRV);
        uint value = strategy.want().daiValue(data.totalSupply);
        uint profit = data.profit;
        uint apy = 100 * profit * 1e18 / value * 365 days / data.timeInvested;

        return apy;
    }

    function logHarvest(uint _totalSupply, uint _profit) external {
        APYData storage data = latestData[msg.sender];
        if (data.timeInvested == 0) {
            data.timeInvested = block.timestamp;
            data.totalSupply = _totalSupply;
            data.profit = _profit;
            return;
        }

        uint timeInvested = block.timestamp - data.timeInvested;
        data.timeInvested = timeInvested;
        data.totalSupply = _totalSupply;
        data.profit = _profit;
        emit Harvest(msg.sender, timeInvested, _totalSupply, _profit);
    }

    function calculateAPYByVault(address vault) external view returns (uint256) {
        address token = address(CritVault(vault).token());
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
        address token = reward.stakingToken();
        uint tokenDecimals = 10**uint256(ERC20(token).decimals());
        uint totalSupply = reward.totalSupply();
        if (totalSupply == 0) {
            totalSupply = tokenDecimals;
        }

        uint rewardPerTokenPerSecond = reward.rewardRate() * tokenDecimals / totalSupply;
        uint tokenPrice = token.perETH();
        uint critPrice = crit.perETH();

        uint apy = 100 * rewardPerTokenPerSecond * (365 days) * critPrice / tokenPrice;
        return apy;
    }
}