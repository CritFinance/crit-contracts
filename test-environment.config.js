const { projectId } = require('./secrets.json')

const deployer = "0x71d2506Dc153458F79FA9CF1adcE270ef3B04B46"
const unlocked_accounts = [deployer]

module.exports = {
    accounts: {
        amount: 10, // Number of unlocked accounts
        ether: 100, // Initial balance of unlocked accounts (in ether)
    },
    setupProvider: (baseProvider) => {
        const { GSNDevProvider } = require('@openzeppelin/gsn-provider');
        const { accounts } = require('@openzeppelin/test-environment');

        return new GSNDevProvider(baseProvider, {
            txfee: 1,
            useGSN: false,
            ownerAddress: accounts[8],
            relayerAddress: accounts[9],
        });
    },
    node: { // Options passed directly to Ganache client
        fork: `wss://mainnet.infura.io/ws/v3/${projectId}`,
        unlocked_accounts: unlocked_accounts,
        gasLimit: 12000000
    }
};