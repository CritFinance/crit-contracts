// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./ICritAMMSignal.sol";
import "../../../interfaces/IUniswapV2Router02.sol";
import "../../../interfaces/IUniswapV2Pair.sol";
import "../../utils/CritStat.sol";

interface ICrit {
    function rewardsDistribution() external view returns(address);
}

interface IRewardDistributions {
    function distributions() external view returns(address[] memory);
}

contract CritAMM {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Router02 private constant uniswap = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant CRIT = 0xf00eA2f3761a730f414aeE6DfDC7857b6a3Ef086;
    IUniswapV2Pair private constant LP = IUniswapV2Pair(0x56ebF3ec044043efbcC13D66E46cc30bD0D35fD2);

    CritStat private constant stat = CritStat(0x48a34b6FDaFe5D548dB23133a26eC85247Ca6EDC);
    address private constant treasuryFund = 0x8c7A440962D783A234DA45682dDd809515a7459F;

    address public ammSignal;

    address public critStrategy;
    address public wethStrategy;

    address public governance;
    address public strategist;

    uint256 public poolSize = 200;    // 2%
    uint256 public POOL_MAX = 10000;  // equals TVL size.

    modifier onlyGovernance {
        require(msg.sender == governance, "governance");
        _;
    }

    modifier authStrategist {
        require(msg.sender == strategist || msg.sender == governance, "strategist");
        _;
    }

    modifier authWithdraw {
        require(msg.sender == critStrategy || msg.sender == wethStrategy || msg.sender == governance, "auth");
        _;
    }

    constructor() public {
        governance = msg.sender;
        strategist = msg.sender;

        IERC20(address(LP)).approve(address(uniswap), uint(~0));
        IERC20(WETH).approve(address(uniswap), uint(~0));
        IERC20(CRIT).approve(address(uniswap), uint(~0));
    }

    function setGovernance(address _governance) external onlyGovernance {
        require(_governance != address(0), "governance");
        governance = _governance;
    }

    function setStrategist(address _strategist) external authStrategist {
        require(_strategist != address(0), "strategist");
        strategist = _strategist;
    }

    function setPoolSize(uint256 _poolSize) external authStrategist {
        poolSize = _poolSize;
    }

    function setStrategy(address token, address strategy) external onlyGovernance {
        if (token == CRIT) {
            critStrategy = strategy;
        } else if (token == WETH) {
            wethStrategy = strategy;
        } else {
            revert("token");
        }
    }

    function setAMMSignal(address _signal) external onlyGovernance {
        require(_signal != address(0x0), "0x0");
        ammSignal = _signal;
    }

    function deposit(address token, uint amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawAll(address token) external authWithdraw {
        withdraw(token, tokenBalance(token));
    }

    function withdraw(address token, uint amount) public {
        if (token == CRIT) {
            require(msg.sender == critStrategy || msg.sender == governance, "auth");
            _transfer(CRIT, amount, critStrategy);
        } else if (token == WETH) {
            require(msg.sender == wethStrategy || msg.sender == governance, "auth");
            _transfer(WETH, amount, wethStrategy);
        } else {
            require(msg.sender == governance, "governance");
            IERC20(token).safeTransfer(treasuryFund, amount);
        }
    }

    function _transfer(address _token, uint _amount, address _to) private {
        IERC20 token = IERC20(_token);
        uint balance = token.balanceOf(address(this));
        if (balance >= _amount) {
            token.safeTransfer(_to, _amount);
            return;
        }

        uniswap.removeLiquidity(WETH, CRIT, IERC20(address(LP)).balanceOf(address(this)), 0, 0, address(this), block.timestamp);
        balance = token.balanceOf(address(this));
        if (balance >= _amount) {
            token.safeTransfer(_to, _amount);
            addLiquidityToUniswap();
            return;
        }

        uint _need = _amount.sub(balance);
        require(token.balanceOf(treasuryFund) >= _need, "not enough amount");
        token.safeTransferFrom(treasuryFund, address(this), _need);
        token.safeTransfer(_to, _amount);
    }

    function addLiquidityToUniswap() public {
        require(msg.sender == strategist || msg.sender == critStrategy || msg.sender == wethStrategy || msg.sender == governance, "auth");
        uint targetPoolSize = stat.TVL().mul(poolSize / 2).div(POOL_MAX);

        address[] memory path = new address[](2);
        path[0] = DAI;
        path[1] = WETH;
        uint[] memory amounts = uniswap.getAmountsOut(targetPoolSize, path);
        uint ethAmount = amounts[1];
        uint _ethLP = _tokenBalanceInLP(WETH);
        if (_ethLP >= ethAmount) {
            return;
        }

        uint supplyETH = ethAmount.sub(_ethLP);
        uint supplyCRIT = _tokenBalance(CRIT);
        uniswap.addLiquidity(WETH, CRIT, supplyETH, supplyCRIT, 0, 0, address(this), block.timestamp);
    }

    function executeMarketMaking() external authStrategist {
        (ICritAMMSignal.Signal signal, uint amount) = ICritAMMSignal(ammSignal).getSignal();
        require(signal != ICritAMMSignal.Signal.idle, "no signal");

        if (signal == ICritAMMSignal.Signal.buy) {
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = CRIT;
            uniswap.swapTokensForExactTokens(amount, uint(~0), path, address(this), block.timestamp);
        } else if (signal == ICritAMMSignal.Signal.sell) {
            address[] memory path = new address[](2);
            path[0] = CRIT;
            path[1] = WETH;
            uniswap.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp);
        }
    }

    function supplyLiquidity() public authStrategist {
        removeLiquidityAll();
        addLiquidityToUniswap();
    }

    function addLiquidity(uint supplyETH, uint supplyCRIT) public authStrategist {
        uniswap.addLiquidity(WETH, CRIT, supplyETH, supplyCRIT, supplyETH*998/1000, supplyCRIT*998/1000, address(this), block.timestamp);
    }

    function removeLiquidity(uint lpAmount, uint wethMin, uint critMin) public authStrategist {
        uniswap.removeLiquidity(WETH, CRIT, lpAmount, wethMin, critMin, address(this), block.timestamp);
    }

    function removeLiquidityAll() private {
        uint lpBalance = IERC20(address(LP)).balanceOf(address(this));
        if (lpBalance == 0) {
            return;
        }
        uniswap.removeLiquidity(WETH, CRIT, lpBalance, 0, 0, address(this), block.timestamp);
    }

    function _tokenBalance(address token) private view returns(uint) {
        return IERC20(token).balanceOf(address(this));
    }

    function _tokenBalanceInLP(address token) private view returns(uint) {
        uint shares = LP.balanceOf(address(this));
        uint totalSupply = LP.totalSupply();

        return IERC20(token).balanceOf(address(LP)).mul(shares).div(totalSupply);
    }

    function tokenBalance(address token) public view returns(uint) {
        return _tokenBalance(token).add(_tokenBalanceInLP(token));
    }
}