const { contract, web3 } = require('@openzeppelin/test-environment')
const { time, BN, expectRevert } = require('@openzeppelin/test-helpers')
const { takeSnapshot, restoreSnapshot } = require('./utils')({web3: web3})
const { expect } = require('chai')

const {
    Crit,
    DAIReward, USDCReward, USDTReward,
    WETHReward, BALReward, LINKReward, UNIReward,
    SNXReward, CRVReward, MKRReward, COMPReward
} = require('./contracts.json')

describe("Crit Mint", function () {
    let snapshotId
    before(async function() {
        this.crit = await (contract.fromArtifact("Crit")).at(Crit)
    })

    beforeEach(async function () {
        snapshotId = await takeSnapshot()
    });

    afterEach(async() => {
        await restoreSnapshot(snapshotId)
    })

    it("Crit initial mint test", async function() {
        let totalSupply = await this.crit.totalSupply()
        if (totalSupply.gtn(0)) return  // means working well!!

        let now = await time.latest()

        if (now.lt(new BN("1601863200"))) {
            await expectRevert(
                this.crit.mint(), "supplyToMint"
            )
            await time.increaseTo(1601863200 - 3)
            now = await time.latest()
            console.log('cant mint at',now.toNumber())
            await expectRevert(
                this.crit.mint(), "supplyToMint"
            )
            await time.increase(2)
            totalSupply = await this.crit.totalSupply()
            expect(totalSupply.toString()).to.equal("0")

            now = await time.latest()
            console.log("mint now:", now.toNumber())
        }
        await this.crit.mint()
        totalSupply = await this.crit.totalSupply()
        expect(web3.utils.fromWei(totalSupply)).to.equal("358025")

        const dev = "0xE0B6f711f0C015b3111f3c124C80f3Aa7cE3A502"
        let rewards = [ DAIReward, USDCReward, USDTReward,
            WETHReward, BALReward, LINKReward, UNIReward, SNXReward, CRVReward, MKRReward, COMPReward, dev ]

        let sum = new BN()
        for (reward of rewards) {
            let balance = await this.crit.balanceOf(reward)
            console.log(web3.utils.fromWei(balance), "CRIT")
            sum = sum.add(balance)
        }

        console.log("TOTAL:", web3.utils.fromWei(sum), "CRIT")
    })
})