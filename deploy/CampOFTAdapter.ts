import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

const tokenName = 'WETH9'
const bridgeName = 'CampBridge'
const contractName = 'CampOFTAdapter'

const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre

    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    assert(deployer, 'Missing named deployer account')

    console.log(`Network: ${hre.network.name}`)
    console.log(`Deployer: ${deployer}`)

    // This is an external deployment pulled in from @layerzerolabs/lz-evm-sdk-v2
    //
    // @layerzerolabs/toolbox-hardhat takes care of plugging in the external deployments
    // from @layerzerolabs packages based on the configuration in your hardhat config
    //
    // For this to work correctly, your network config must define an eid property
    // set to `EndpointId` as defined in @layerzerolabs/lz-definitions
    //
    // For example:
    //
    // networks: {
    //   fuji: {
    //     ...
    //     eid: EndpointId.AVALANCHE_V2_TESTNET
    //   }
    // }
    const endpointV2Deployment = await hre.deployments.get('EndpointV2')

    // The token address must be defined in hardhat.config.ts
    // If the token address is not defined, the deployment will log a warning and skip the deployment
    if (hre.network.config.oftAdapter == null) {
        console.warn(`oftAdapter not configured on network config, skipping OFTWrapper deployment`)

        return
    }

    const { address: wethAddress } = await deploy(tokenName, {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        waitConfirmations: 5,
    })

    console.log(`Deployed contract: ${wethAddress}, network: ${hre.network.name}, address: ${wethAddress}`)

    const { address: oftAdapterAddress } = await deploy(contractName, {
        from: deployer,
        args: [
            wethAddress, // token address
            endpointV2Deployment.address, // LayerZero's EndpointV2 address
            deployer, // owner
        ],
        log: true,
        skipIfAlreadyDeployed: true,
        waitConfirmations: 5,
    })

    console.log(`Deployed contract: ${contractName}, network: ${hre.network.name}, address: ${oftAdapterAddress}`)

    const { address: bridgeAddress } = await deploy(bridgeName, {
        from: deployer,
        args: [wethAddress, oftAdapterAddress],
        log: true,
        skipIfAlreadyDeployed: true,
        waitConfirmations: 5,
    })

    console.log(`Deployed contract: ${bridgeName}, network: ${hre.network.name}, address: ${bridgeAddress}`)
}

deploy.tags = [contractName]

export default deploy
