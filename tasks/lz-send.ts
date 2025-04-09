import { BigNumberish, BytesLike } from 'ethers'
import { task } from 'hardhat/config'
import 'hardhat/types/config'

import { getNetworkNameForEid, types } from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'
import { Options, addressToBytes32 } from '@layerzerolabs/lz-v2-utilities'

interface Args {
    amount: string
    to: string
    toeid: EndpointId
}

interface SendParam {
    dstEid: EndpointId // Destination endpoint ID, represented as a number.
    to: BytesLike // Recipient address, represented as bytes.
    amountLD: BigNumberish // Amount to send in local decimals.
    minAmountLD: BigNumberish // Minimum amount to send in local decimals.
    extraOptions: BytesLike // Additional options supplied by the caller to be used in the LayerZero message.
    composeMsg: BytesLike // The composed message for the send() operation.
    oftCmd: BytesLike // The OFT command to be executed, unused in default OFT implementations.
}

// send tokens from a contract on one network to another
task('lz:oft:send', 'Sends tokens from either OFT or OFTAdapter')
    .addParam('to', 'contract address on network B', undefined, types.string)
    .addParam('toeid', 'destination endpoint ID', undefined, types.eid)
    .addParam('amount', 'amount to transfer in token decimals', undefined, types.string)
    .setAction(async (taskArgs: Args, { ethers, deployments }) => {
        const toAddress = taskArgs.to
        const eidB = taskArgs.toeid

        // Get the contract factories
        const oftDeployment =
            hre.network.name === 'camp-v2-testnet' || hre.network.name === 'op-sepolia-testnet'
                ? await deployments.get('NativeCampOFTAdapter')
                : await deployments.get('CampOFT')

        const [signer] = await ethers.getSigners()

        console.log('oft contract: ', oftDeployment.address)

        // Create contract instances
        const oftContract = new ethers.Contract(oftDeployment.address, oftDeployment.abi, signer)

        const decimals = 18
        const amount = ethers.utils.parseUnits(taskArgs.amount, decimals)
        const options = Options.newOptions().addExecutorLzReceiveOption(200000, 0).toBytes()

        // Now you can interact with the correct contract
        const oft = oftContract

        const sendParam: SendParam = {
            dstEid: eidB,
            to: addressToBytes32(toAddress),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: ethers.utils.arrayify('0x'), // Assuming no composed message
            oftCmd: ethers.utils.arrayify('0x'), // Assuming no OFT command is needed
        }
        // Get the quote for the send operation
        const feeQuote = await oft.quoteSend(sendParam, false)
        const nativeFee = feeQuote.nativeFee
        console.log({ amount, nativeFee })

        console.log(`sending ${taskArgs.amount} token(s) to network ${getNetworkNameForEid(eidB)} (${eidB})`)

        const innerTokenAddress = await oft.token()

        // // If the token address !== address(this), then this is an OFT Adapter
        if (innerTokenAddress !== oft.address) {
            console.log('using adapter')
            const r = await oft.send(sendParam, { nativeFee: nativeFee, lzTokenFee: 0 }, signer.address, {
                value: nativeFee.add(amount),
            })
            console.log(`Send tx initiated. See: https://layerzeroscan.com/tx/${r.hash}`)
        } else {
            console.log('using oft')
            const r = await oft.send(sendParam, { nativeFee: nativeFee, lzTokenFee: 0 }, signer.address, {
                value: nativeFee,
            })
            console.log(`Send tx initiated. See: https://layerzeroscan.com/tx/${r.hash}`)
        }
    })
