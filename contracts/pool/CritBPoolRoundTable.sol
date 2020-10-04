// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/GSN/Context.sol";

import "../../interfaces/Vault.sol";
import "../../interfaces/OneSplitAudit.sol";
import "../../interfaces/Controller.sol";

interface ICritBPool {
    function remove_liquidity(address _token, uint256 _amount) external;
    function add_liquidity(address _token, uint256 _amount) external;
}

contract CritBPoolRoundTable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public governance;
    address public controller;
    address public strategist;
    address public bpool;
    address public onesplit;

    address private WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    mapping (address => address) public vaults;

    uint256 public tolerance = 500;         // 5%
    uint256 public TOLERANCE_MAX = 10000;

    modifier onlyGovernance {
        require(msg.sender == governance, 'governance');
        _;
    }

    modifier authStrategist {
        require(msg.sender == strategist || msg.sender == governance, 'auth');
        _;
    }

    constructor(address _controller, address _bpool) public {
        governance = msg.sender;
        controller = _controller;
        strategist = msg.sender;
        bpool = _bpool;
        onesplit = address(0x50FDA034C0Ce7a8f7EFDAebDA7Aa7cA21CC1267e);
    }

    function setBPool(address _bpool) external onlyGovernance {
        bpool = _bpool;
    }

    function setTolerance(uint256 _tolerance) external onlyGovernance {
        tolerance = _tolerance;
    }

    function setOneSplit(address _onesplit) external onlyGovernance {
        onesplit = _onesplit;
    }

    function setVault(address _token, address _vault) external onlyGovernance {
        vaults[_token] = _vault;
    }

    function inCaseTokensGetStuck(address _token, uint _amount) external onlyGovernance {
        ICritBPool(bpool).remove_liquidity(_token, _amount);
    }

    function withdraw(address token, uint256 amount) external authStrategist {
        address reward = Controller(controller).rewards();
        IERC20(token).safeTransfer(reward, amount);
    }

    function setStrategist(address _strategist) external authStrategist {
        strategist = _strategist;
    }

    function getPnL(address _token) public view returns(int) {
        IERC20 erc20 = IERC20(_token);
        address vault = vaults[_token];
        uint a = erc20.balanceOf(vault);
        uint b = Controller(controller).balanceOf(vault);

        uint principle = IERC20(vaults[_token]).totalSupply();

        return int(a + b) - int(principle);
    }

    // 1. sell _token if balance exceeds tolerance
    function harvest(address[] calldata _tokens) external authStrategist {
        for (uint i=0; i<_tokens.length; i++) {
            address token = _tokens[i];
            int pnl = getPnL(token);
            if (pnl > 0) {
                uint256 profit = uint256(pnl);
                // has exceeded tolerance
                if (IERC20(vaults[token]).totalSupply().mul(tolerance).div(TOLERANCE_MAX) < profit) {
                    ICritBPool(bpool).remove_liquidity(token, profit);
                }
            }
        }
    }

    // 2. liquidate _token to WETH
    function liquidate(address _token, uint256 _amount, uint256 _minReturn, uint256[] calldata _distribution) external authStrategist {
        require(IERC20(_token).balanceOf(address(this)) >= _amount, 'amount');

        IERC20(_token).safeApprove(onesplit, 0);
        IERC20(_token).safeApprove(onesplit, _amount);

        OneSplitAudit(onesplit).swap(_token, WETH, _amount, _minReturn, _distribution, 0);
    }

    // 3. buy _destToken to adjust pool weight
    // amount should be calculated by the strategist off-chain.
    function fill(address _destToken, uint256 _wethAmount, uint256 _minReturn, uint256[] calldata distribution) external authStrategist {
        require(_destToken != WETH, "WETH");
        require(vaults[_destToken] != address(0), '_destToken');
        require(IERC20(WETH).balanceOf(address(this)) >= _wethAmount, 'insufficient amount');

        IERC20(WETH).safeApprove(onesplit, 0);
        IERC20(WETH).safeApprove(onesplit, _wethAmount);
        OneSplitAudit(onesplit).swap(WETH, _destToken, _wethAmount, _minReturn, distribution, 0);

        uint256 sendingBalance = IERC20(_destToken).balanceOf(address(this));
        IERC20(_destToken).safeTransfer(bpool, sendingBalance);
        ICritBPool(bpool).add_liquidity(_destToken, sendingBalance);
    }

    function fillETH(uint256 amount) external authStrategist {
        IERC20(WETH).safeTransfer(bpool, amount);
        ICritBPool(bpool).add_liquidity(WETH, amount);
    }
}