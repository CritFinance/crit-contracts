const { contract, web3 } = require('@openzeppelin/test-environment')

const CritAPYv2 = contract.fromArtifact("CritAPYv2")

describe("CRIT APY", function () {
    before(async function() {
        await CritAPYv2.detectNetwork()
        await CritAPYv2.link('UniswapPriceOracle', "0x355A4020F0384efC11b145569Ea921b648FDA15a")
        this.apy = await CritAPYv2.new()
    })

    it("print reward APY", async function() {
        const tokens = ["DAI", "USDC", "USDT", "WETH", "BAL", "LINK", "UNI", "SNX", "CRV", "MKR", "COMP"]
        for (token of tokens) {
            let rewardAddress = require('./contracts.json')[`${token}Reward`]
            let apy = await this.apy.calculateAPYByReward(rewardAddress)
            let apyString = web3.utils.fromWei(apy)
            console.log(token, apyString, "%")
        }
    })
})