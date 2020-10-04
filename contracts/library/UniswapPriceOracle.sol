// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../../interfaces/IUniswapV2Router02.sol";

library UniswapPriceOracle {
    using SafeMath for uint256;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    IUniswapV2Router02 public constant uniswap = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function perETH(address token) public view returns(uint) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        return uniswap.getAmountsOut(10**uint256(ERC20(token).decimals()), path)[1];
    }

    function perDAI(address token) public view returns(uint) {
        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = WETH;
        path[2] = DAI;

        return uniswap.getAmountsOut(10**uint256(ERC20(token).decimals()), path)[2];
    }

    function ethValue(address token, uint amount) external view returns(uint) {
        if (token == WETH) {
            return amount;
        }

        return amount.mul(perETH(token)).div(10**uint256(ERC20(token).decimals()));
    }

    function daiValue(address token, uint amount) external view returns(uint) {
        if (token == WETH) {
            return amount.mul(1e18).div(perETH(DAI));
        }

        return amount.mul(perDAI(token)).div(10**uint256(ERC20(token).decimals()));
    }

    function swapAmountFromETH(address token, uint ethAmount) external view returns(uint) {
        if (token == WETH) {
            return ethAmount;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;
        return uniswap.getAmountsOut(ethAmount, path)[1];
    }
}