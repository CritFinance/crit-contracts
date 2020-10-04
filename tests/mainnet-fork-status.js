const { contract } = require('@openzeppelin/test-environment')
const { expect } = require('chai')

const {
    Crit,
    Controller, CritBPool, CritBPoolRoundTable,
    Timelock
} = require('./contracts.json')

const tokens = ["DAI", "USDC", "USDT", "yCRV", "WETH", "BAL", "LINK", "UNI", "SNX", "CRV", "MKR", "COMP"]
const tokenAddress = {
    "DAI": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
    "USDC": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    "USDT": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
    "yCRV": "0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8",
    "WETH": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "BAL": "0xba100000625a3754423978a60c9317c58a424e3D",
    "LINK": "0x514910771AF9Ca656af840dff83E8264EcF986CA",
    "UNI": "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984",
    "SNX": "0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F",
    "CRV": "0xD533a949740bb3306d119CC777fa900bA034cd52",
    "MKR": "0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2",
    "COMP": "0xc00e94Cb662C3520282E6f5717214004A7f26888"
}

const CritVault = contract.fromArtifact("CritVault")
const CritStrategy = contract.fromArtifact("StrategyBalancerPool")
const StrategyController = contract.fromArtifact("StrategyControllerV2")
const CritBPoolContract = contract.fromArtifact("CritBPool")
const CritBPoolRoundTableContract = contract.fromArtifact("CritBPoolRoundTable")
const StakingReward = contract.fromArtifact("StakingRewards")
const TimelockContract = contract.fromArtifact("Timelock")
const deployer = "0x71d2506Dc153458F79FA9CF1adcE270ef3B04B46"

describe("CRIT", function () {
    before(async function () {
        this.controller = await StrategyController.at(Controller)
    })

    it("timelock admin", async function() {
        let timelock = await TimelockContract.at(Timelock)
        expect(await timelock.admin()).to.equal(deployer)
    })

    it("check VAULT - CONTROLLER - STRATEGY", async function() {
        for (token of tokens) {
            let vault = require('./contracts.json')[`${token}Vault`]
            let strategy = require('./contracts.json')[`${token}Strategy`]

            expect(await this.controller.vaults(strategy)).to.equal(vault)
            expect(await this.controller.strategies(vault)).to.equal(strategy)

            let critVault = await CritVault.at(vault)
            expect(await critVault.token()).to.equal(tokenAddress[token])
            expect(await critVault.controller()).to.equal(Controller)
            expect(await critVault.governance()).to.equal(Timelock)

            let critStrategy = await CritStrategy.at(strategy)
            expect(await critStrategy.want()).to.equal(tokenAddress[token])
            expect(await critStrategy.controller()).to.equal(Controller)
            expect(await critStrategy.governance()).to.equal(Timelock)
        }
    })

    it("check BPool", async function() {
        let critBPool = await CritBPoolContract.at(CritBPool)
        let critBPoolRoundTable = await CritBPoolRoundTableContract.at(CritBPoolRoundTable)
        const tokens = ["WETH", "BAL", "LINK", "UNI", "SNX", "CRV", "MKR", "COMP"]
        for (token of tokens) {
            let strategy = require('./contracts.json')[`${token}Strategy`]
            expect(await critBPool.strategies(tokenAddress[token])).to.equal(strategy)

            let critStrategy = await CritStrategy.at(strategy)
            expect(await critStrategy.pool()).to.equal(CritBPool)
            expect(await critBPoolRoundTable.vaults(tokenAddress[token])).to.equal(require('./contracts.json')[`${token}Vault`])
        }
    })

    it ("rewards", async function() {
        for (token of tokens.filter(token => token !== "yCRV")) {
            let reward = await StakingReward.at(require('./contracts.json')[`${token}Reward`])
            expect(await reward.rewardsToken()).to.equal(Crit)
            expect(await reward.stakingToken()).to.equal(require('./contracts.json')[`${token}Vault`])
        }
    })
})