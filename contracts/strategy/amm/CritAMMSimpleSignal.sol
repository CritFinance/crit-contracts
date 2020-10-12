// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./ICritAMMSignal.sol";
import "../../../interfaces/IUniswapV2Router02.sol";
import "../../../interfaces/IUniswapV2Pair.sol";

contract CritAMMSimpleSignal is ICritAMMSignal {
    using SafeMath for uint256;

    IUniswapV2Router02 private constant uniswap = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Pair private constant LP = IUniswapV2Pair(0x56ebF3ec044043efbcC13D66E46cc30bD0D35fD2);
    IUniswapV2Pair private constant DAI_WETH = IUniswapV2Pair(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11);

    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant CRIT = 0xf00eA2f3761a730f414aeE6DfDC7857b6a3Ef086;

    address public strategist;

    uint public low;        // in $, 18 decimal
    uint public high;       // in $, 18 decimal

    constructor() public {
        strategist = msg.sender;
    }

    // be calculated on off-chain.
    function setLow(uint _low) external {
        require(msg.sender == strategist, "auth");
        low = _low;
    }

    // be calculated on off-chain.
    function setHigh(uint _high) external {
        require(msg.sender == strategist, "auth");
        high = _high;
    }

    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "auth");
        require(_strategist != address(0), "0x0");
        strategist = _strategist;
    }

    function lowETHPrice() public view returns(uint256) {
        return low * 1e18 / ethPrice();
    }

    function ethPrice() public view returns(uint256) {
        (uint dai, uint weth, ) = DAI_WETH.getReserves();
        return uniswap.quote(1e18, weth, dai);
    }

    function critPricePerDAI() public view returns(uint256) {
        (uint dai, uint weth, ) = DAI_WETH.getReserves();
        return uniswap.quote(critPricePerETH(), weth, dai);
    }

    function critPricePerETH() public view returns(uint256) {
        (uint eth, uint crit, ) = LP.getReserves();
        return uniswap.quote(1e18, crit, eth);
    }

    function getSignal() override public view returns(Signal, uint256) {
        uint critPrice = critPricePerETH();
        uint _lowPrice = low * 1e18 / ethPrice();
        uint _highPrice = high * 1e18 / ethPrice();

        if (critPrice * 1001 / 1000 < _lowPrice) {
            uint amount = 0;
            (uint w, uint c, ) = LP.getReserves();
            uint priceImpact = _lowPrice.sub(critPrice).mul(1e18).div(_lowPrice);
            uint impactAmount = c.mul(priceImpact).div(1e18);
            uint unit = impactAmount.div(50);
            amount = impactAmount / 2;
            w += uniswap.getAmountIn(amount, w, c);
            c -= amount;
            critPrice = uniswap.quote(1e18, c, w);
            while(critPrice < _lowPrice) {
                w += uniswap.getAmountIn(unit, w, c);
                c -= unit;
                amount += unit;
                critPrice = uniswap.quote(1e18, c, w);
            }
            amount -= unit;
            return (Signal.buy, amount);
        } else if (critPrice * 1000 / 1001 > _highPrice) {
            uint amount = 0;
            (uint w, uint c, ) = LP.getReserves();
            uint priceImpact = critPrice.sub(_highPrice).mul(1e18).div(critPrice);
            uint impactAmount = c.mul(priceImpact).div(1e18);
            uint unit = impactAmount.div(50);
            amount = impactAmount / 2;
            w -= uniswap.getAmountOut(amount, c, w);
            c += amount;
            critPrice = uniswap.quote(1e18, c, w);
            while (critPrice > _highPrice) {
                w -= uniswap.getAmountOut(unit, c, w);
                c += unit;
                amount += unit;
                critPrice = uniswap.quote(1e18, c, w);
            }

            amount -= unit;

            return (Signal.sell, amount);
        }

        return (Signal.idle, 0);
    }
}