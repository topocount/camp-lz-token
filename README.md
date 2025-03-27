
## 1) Developing Contracts

#### Installing dependencies

We recommend using `pnpm` as a package manager (but you can of course use a package manager of your choice):

```bash
pnpm install
```

#### Compiling your contracts

This project supports both `hardhat` and `forge` compilation. By default, the `compile` command will execute both:

```bash
pnpm compile
```

If you prefer one over the other, you can use the tooling-specific commands:

```bash
pnpm compile:forge
pnpm compile:hardhat
```


#### Running tests

```bash
pnpm test
```


## 2) Deploying Contracts

Set up deployer wallet/account:

- Rename `.env.example` -> `.env`
- Choose your preferred means of setting up your deployer wallet/account:

```
MNEMONIC="test test test test test test test test test test test junk"
or...
PRIVATE_KEY="0xabc...def"
```

- Fund this address with the corresponding chain's native tokens you want to deploy to.

To deploy your contracts to your desired blockchains, run the following command in your project's folder:

```bash
npx hardhat lz:deploy --tags CampOFT # choose target network in dialog
# the CampOFTAdapter script deploys the wrapper token and the Bridge helper contract as well
npx hardhat lz:deploy --tags CampOFTAdapter # choose target network in dialog
```

More information about available CLI arguments can be found using the `--help` flag:

```bash
npx hardhat lz:deploy --help
# wire up the two implementations in the LayerZero network
# this is actually very slick
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts
```

## 3) Sending CAMP

[LayerZero endpoint ids] are used to identify where to send payloads in the omnichain network

```bash
npx hardhat lz:deploy --help
npx hardhat lz:oft:send --to <recipient wallet> --toeid <LayerZero endpoint id to send to> --amount <number denominated in eth> --network <network name from hardhat.config.ts to send from>
# EXAMPLES
# NOTE these functions assume you are holding wCAMP to test the cross-chain integration
source .env
cast send <WETH9 address> --value 0.05ether --rpc-url $RPC_URL_CAMP --mnemonic $MNEMONIC
# the CampBridge works but this is just more straightforward for testing the LZ integration, since the Bridge is basically a convenience wrapper that is sufficiently tested in the unit tests and would waste gas on public testnets
npx hardhat lz:oft:send --to 0x10e11A95D03585737B3e62b82F495b819fFf0D1B --toeid 40161 --amount 0.005 --network camp-v2-testnet
npx hardhat lz:oft:send --to 0x10e11A95D03585737B3e62b82F495b819fFf0D1B --toeid 40295 --amount 0.005 --network sepolia-testnet
```

## Further Work

- battle test a deployment with larger quantites, potentially on a fork (and manually execute the transfer)
- Utilize the provided NativeOFTAdapter and cut out a bunch of this code
- full test coverage beyond the parts I hacked on. I didn't write any tests for the sepolia CAMP OFT because we only need
  to use the off-the-shelf one, but it's good to cover our bases

[LayerZero endpoint ids]: https://docs.layerzero.network/v2/deployments/deployed-contracts
