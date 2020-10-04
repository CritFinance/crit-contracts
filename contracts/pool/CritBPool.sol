// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/BFactory.sol";
import "../library/UniswapPriceOracle.sol";

contract CritBPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using UniswapPriceOracle for address;

    struct TokenWeight {
        address token;
        uint256 amount;
        uint256 denorm;
    }

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public governance;
    address public strategist;
    address public roundTable;

    BFactory public factory = BFactory(0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd);
    BPool public pool;

    mapping (address => address) public strategies;
    uint256 public rebalancedAt;

    modifier onlyGovernance {
        require(msg.sender == governance, 'governance');
        _;
    }

    constructor() public {
        pool = factory.newBPool();
        pool.setSwapFee(15e14);

        governance = msg.sender;
        roundTable = msg.sender;
        strategist = msg.sender;
    }

    // ************************************************************** Controller
    function setSwapFee(uint256 _swapFee) external onlyGovernance {
        pool.setSwapFee(_swapFee);
    }

    function setStrategy(IERC20 _token, address _strategy) external onlyGovernance {
        strategies[address(_token)] = _strategy;
    }

    function setRoundTable(address _roundTable) external onlyGovernance {
        roundTable = _roundTable;
    }

    // **************************************************************
    function setPublicSwap(bool _swap) public {
        require(msg.sender == strategist || msg.sender == governance, "auth");
        if (_swap == true) {
            require(rebalancedAt + 5 <= block.number, 'not enough block');
            require(checkWellBalanced(), 'need rebalance');
        }
        pool.setPublicSwap(_swap);
    }

    function getTokenWeight(address[] calldata tokens) public view returns(TokenWeight[] memory) {
        TokenWeight[] memory tokenWeights = new TokenWeight[](tokens.length);
        uint[] memory ethValues = new uint[](tokens.length);
        uint[] memory balances = new uint[](tokens.length);

        uint256 minETHValue = uint256(~0);
        uint i;
        for (i=0; i<tokens.length; i++) {
            ERC20 token = ERC20(tokens[i]);
            balances[i] = balanceOf(address(token));
            ethValues[i] = address(token).ethValue(balances[i]);
            if (ethValues[i] < minETHValue) {
                minETHValue = ethValues[i];
            }
        }

        uint256 totalDenorm;
        for (i=0; i<tokens.length; i++) {
            tokenWeights[i].token = tokens[i];
            tokenWeights[i].denorm = uint(2e18).mul(ethValues[i]).div(minETHValue);
            tokenWeights[i].amount = balances[i];
            totalDenorm = totalDenorm.add(tokenWeights[i].denorm);
        }

        require(totalDenorm < 50e18, 'totalDenorm');

        return tokenWeights;
    }

    function compareUniswap(address token) public view returns(bool) {
        uint256 inputETHAmount = 1e18;
        uint256 poolOutput = pool.calcOutGivenIn(
            pool.getBalance(WETH),
            pool.getDenormalizedWeight(WETH),
            pool.getBalance(token),
            pool.getDenormalizedWeight(token),
            inputETHAmount,
            pool.getSwapFee()
        );

        uint256 uniswapOutput = token.swapAmountFromETH(inputETHAmount);
        uint256 decimal = 10**uint256(ERC20(token).decimals());

        uint MIN = decimal.mul(995).div(1000);
        uint MAX = decimal.mul(1005).div(1000);
        uint ratio = poolOutput.mul(decimal).div(uniswapOutput);
        if (MIN < ratio && ratio < MAX) {
            return true;
        }

        return false;
    }

    function checkWellBalanced() public view returns(bool) {
        address[] memory tokens = pool.getCurrentTokens();

        for (uint i=0; i<tokens.length; i++) {
            address token = tokens[i];
            if (token == WETH) continue;
            if (compareUniswap(token)) continue;

            return false;
        }

        return true;
    }

    //
    function rebalance(address[] calldata tokens) external {
        require(msg.sender == strategist || msg.sender == governance, "auth");
        rebalancedAt = block.number;
        setPublicSwap(false);
        bindPool(getTokenWeight(tokens));
    }

    function bindPool(TokenWeight[] memory _tokenWeight) private {
        address[] memory unboundTokens = pool.getCurrentTokens();

        for (uint256 i=0; i< _tokenWeight.length; i++) {
            TokenWeight memory weight = _tokenWeight[i];
            require(strategies[weight.token] != address(0), '!token');
            require(balanceOf(weight.token) >= weight.amount, '!amount');

            IERC20(weight.token).safeApprove(address(pool), 0);
            IERC20(weight.token).safeApprove(address(pool), weight.amount);
            if (pool.isBound(weight.token)) {
                pool.rebind(weight.token, weight.amount, weight.denorm);
            } else {
                pool.bind(weight.token, weight.amount, weight.denorm);
            }

            for (uint256 j=0; j<unboundTokens.length; j++) {
                if (weight.token == unboundTokens[j]) {
                    delete unboundTokens[j];
                    break;
                }
            }
        }

        for (uint256 i=0; i<unboundTokens.length; i++) {
            if (unboundTokens[i] != address(0)) {
                pool.unbind(unboundTokens[i]);
            }
        }
    }

    function add_liquidity(address _token, uint256 _amount) external {
        require(msg.sender == strategies[_token] || msg.sender == roundTable, 'auth');

        if (pool.isPublicSwap() == false || pool.isBound(_token) == false) {
            // not set yet, wait until the operator call rebalance()
            return;
        }

        uint256 oldBalance = pool.getBalance(_token);
        uint256 newBalance = oldBalance.add(_amount);
        uint256 tokenDenorm = pool.getDenormalizedWeight(_token);
        uint256 updatedDenorm = tokenDenorm.mul(newBalance).div(oldBalance);
        if (updatedDenorm > 50e18 || pool.getTotalDenormalizedWeight().add(updatedDenorm.sub(tokenDenorm)) > 50e18) {
            // wait until the operator call rebalance()
            return;
        }

        IERC20(_token).safeApprove(address(pool), 0);
        IERC20(_token).safeApprove(address(pool), _amount);
        pool.rebind(_token, newBalance, updatedDenorm);
    }

    function remove_liquidity(address _token, uint256 _amount) external {
        require(msg.sender == strategies[_token] || msg.sender == roundTable, 'auth');

        uint256 balanceOfThis = IERC20(_token).balanceOf(address(this));
        if (balanceOfThis >= _amount) {
            IERC20(_token).safeTransfer(msg.sender, _amount);
            return;
        }

        uint256 withdrawalAmount = _amount.sub(balanceOfThis);
        uint256 oldBalance = pool.getBalance(_token);
        if (oldBalance < withdrawalAmount) {
            // cause of impermanent loss
            revert("Ask for help on Crit discord");
//            pool.unbind(_token);
//            IERC20(_token).safeTransfer(msg.sender, IERC20(_token).balanceOf(address(this)));
//            return;
        }

        uint256 newBalance = oldBalance.sub(withdrawalAmount);
        uint256 updatedDenorm = pool.getDenormalizedWeight(_token).mul(newBalance).div(oldBalance);
        if (updatedDenorm < 1e18) {
            pool.unbind(_token);
            IERC20(_token).safeTransfer(msg.sender, _amount);
            return;
        }

        pool.rebind(_token, newBalance, updatedDenorm);
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    ///////////////////////// View
    function balanceOf(address _token) public view returns(uint256 balance) {
        balance = IERC20(_token).balanceOf(address(this));
        if (pool.isBound(_token)) {
            balance = balance.add(pool.getBalance(_token));
        }
    }
}