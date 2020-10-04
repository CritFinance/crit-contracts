// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IReward.sol";

import "../library/UniswapPriceOracle.sol";

contract CritStat is Ownable {
    using UniswapPriceOracle for address;

    IVault[] public vaults;
    IReward[] public rewards;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public crit;

    constructor(address _crit) public {
        crit = _crit;
    }

    function addVault(IVault _vault) onlyOwner external {
        vaults.push(_vault);
    }

    function addRewards(IReward _rewards) onlyOwner external {
        rewards.push(_rewards);
    }

    function critPricePerETH() public view returns(uint) {
        return crit.perETH();
    }

    function critPricePerDAI() public view returns(uint) {
        return crit.perDAI();
    }

    function TVL() external view returns (uint) {
        uint wethAmount = 0;

        for (uint i=0; i<vaults.length; i++) {
            IVault vault = vaults[i];
            address token = address(vault.token());
            if (token == WETH) {
                wethAmount += vault.balance();
            } else {
                wethAmount += token.ethValue(vault.balance());
            }
        }

        return ethToUSD(wethAmount);
    }

    function ethToUSD(uint wethAmount) public view returns (uint) {
        return WETH.daiValue(wethAmount);
    }

    function totalUnclaimedRewards(address account) external view returns (uint) {
        uint earned = 0;
        for (uint i=0; i<rewards.length; i++) {
            IReward reward = rewards[i];
            earned += reward.earned(account);
        }
        return earned;
    }
}