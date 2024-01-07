# Transeptor CCIP ERC-4337 smart-account

> **Note**
>
> _The project in active development. The documentation is not complete and some of the features are not implemented yet._
>

- ccip supported networks: https://docs.chain.link/ccip/supported-networks#overview
- [CCIP Explorer](https://ccip.chain.link)

## Prerequisites

- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [Current LTS Node.js version](https://nodejs.org/en/about/releases/)

Verify installation by typing:

```shell
node -v
```

and

```shell
npm -v
```

## Getting Started

1. Install packages

```
npm install
```

2. Compile contracts

```
npx hardhat compile
```

3. Run tests

```
TS_TRANSPILE_NODE=1 npx hardhat test
```

## What is Chainlink CCIP?

**Chainlink Cross-Chain Interoperability Protocol (CCIP)** provides a single, simple, and elegant interface through which dApps and web3 entrepreneurs can securely meet all their cross-chain needs, including token transfers and arbitrary messaging.

![basic-architecture](./img/basic-architecture.png)

With Chainlink CCIP, one can:

- Transfer supported tokens
- Send messages (any data)
- Send messages and tokens

CCIP receiver can be:

- Smart contract that implements `CCIPReceiver.sol`
- EOA

**Note**: If you send a message and token(s) to EOA, only tokens will arrive

To use this project, you can consider CCIP as a "black-box" component and be aware of the Router contract only. If you want to dive deep into it, check the [Official Chainlink Documentation](https://docs.chain.link/ccip).

## Usage

In the next section you can see a couple of basic Chainlink CCIP use case examples. But before that, you need to set up some environment variables.

We are going to use the [`@chainlink/env-enc`](https://www.npmjs.com/package/@chainlink/env-enc) package for extra security. It encrypts sensitive data instead of storing them as plain text in the `.env` file, by creating a new, `.env.enc` file. Although it's not recommended to push this file online, if that accidentally happens your secrets will still be encrypted.

1. Set a password for encrypting and decrypting the environment variable file. You can change it later by typing the same command.

```shell
npx env-enc set-pw
```

2. Now set the following environment variables: `PRIVATE_KEY`, Source Blockchain RPC URL, Destination Blockchain RPC URL. You can see available options in the `.env.example` file:

```shell
ETHEREUM_SEPOLIA_RPC_URL=""
OPTIMISM_GOERLI_RPC_URL=""
ARBITRUM_TESTNET_RPC_URL=""
AVALANCHE_FUJI_RPC_URL=""
POLYGON_MUMBAI_RPC_URL=""
```

To set these variables, type the following command and follow the instructions in the terminal:

```shell
npx env-enc set
```

After you are done, the `.env.enc` file will be automatically generated.

If you want to validate your inputs you can always run the next command:

```shell
npx env-enc view
```

### Faucet

You will need test tokens for some of the examples in this Starter Kit. Public faucets sometimes limit how many tokens a user can create and token pools might not have enough liquidity. To resolve these issues, CCIP supports two test tokens that you can mint permissionlessly so you don't run out of tokens while testing different scenarios.

To get 10\*\*18 units of each of these tokens, use the `faucet` task. Keep in mind that the `CCIP-BnM` test token you can mint on all testnets, while `CCIP-LnM` you can mint only on Ethereum Sepolia. On other testnets, the `CCIP-LnM` token representation is a wrapped/synthetic asset called `clCCIP-LnM`.

```shell
npx hardhat faucet
--receiver <RECEIVER_ADDRESS>
--ccip-bnm <CCIP_BnM_ADDRESS> # Optional
--ccip-lnm <CCIP_LnM_ADDRESS> # Optional
```

For example, to mint tokens on ethereumSepolia run:

```shell
npx hardhat faucet --network ethereumSepolia --receiver <RECEIVER_ADDRESS>
```


### Billing and gaslimit

- billing: https://docs.chain.link/ccip/billing
- gaslimit: The gasLimit specifies the maximum amount of gas CCIP can consume to execute `ccipReceive()` on the contract located on the `destination blockchain`. Read more about gasLimit best practices [here](https://docs.chain.link/ccip/best-practices#setting-gaslimit) (**Unspent gas is not refunded.**).

## Deploy TranseptorAccountFactory on destination chains

To deploy an account factory, run the following command:

Where the list of supported chains consists of (case sensitive):

- optimismGoerli
- arbitrumTestnet
- avalancheFuji
- polygonMumbai

```shell
npx hardhat deploy-smart-account-factory --network <DESTINATION_CHAIN>
```

For example, if you want to deploy an account factory to optimismGoerli you need to deploy this contract on optimismGoerli, by running:

```shell
npx hardhat deploy-account-factory --network optimismGoerli
```

## Deploy DestinationAccountFactoryReceiver on destination chains

The `DestinationAccountFactoryReceiver` with recevice ccip message with encoded dat to call the `createAccount(address owner,uint256 salt)` funtion on the `TranseptorAccountFactory` contract. This will allow user to deploy a `TranseptorAccount` on the destination(L2) chain from source(L1) chain paying the gas fees in native token of source chain so there is no need to bridge assets to the destination chain to pay the gas fees.

To deploy an `DestinationAccountFactoryReceiver`, run the following command:

Where the list of supported chains consists of (case sensitive):

- optimismGoerli
- arbitrumTestnet
- avalancheFuji
- polygonMumbai

```shell
npx hardhat deploy-destination-account-factory-receiver --network <DESTINATION_CHAIN>
```

For example, if you want to deploy an account factory to optimismGoerli you need to deploy this contract on optimismGoerli, by running:

```shell
npx hardhat deploy-destination-account-factory-receiver --network optimismGoerli
```

## Cross-chain Transeptor Smart account deployment
Cross-chain Transeptor Smart account deployment is a two step process. First you need to deploy a `TranseptorAccountFactory` on the destination chain and then you need to deploy a `DestinationAccountFactoryReceiver` on the destination chain. The `DestinationAccountFactoryReceiver` will receive the ccip message with encoded data to call the `createAccount(address owner,uint256 salt)` funtion on the `TranseptorAccountFactory` contract. This will allow user to deploy a `TranseptorAccount` on the destination(L2) chain from source(L1) chain paying the gas fees in native token of source chain so there is no need to bridge assets to the destination chain to pay the gas fees.

All transactions will have `ethereumSepolia` as the source chain and the destination chain will be the chain where the `DestinationAccountFactoryReceiver` is deployed.

Where the list of supported destination chains consists of (case sensitive):

- optimismGoerli
- arbitrumTestnet
- avalancheFuji
- polygonMumbai

To deploy a cross-chain transeptor smart account, run the following command:

```shell  
npx hardhat ccip-smart-account-deploy 
--network ethereumSepolia
--owner <OWNER_ADDRESS>
--salt <SALT>
--destinationBlockchain <Destination Chain>
--pay-fees-in <Native | LINK>
```

This command with send a ccip message to an `DestinationAccountFactoryReceiver` deployed on a destination chain(L2). After the transctoin reaches finility on destination chain you user can start using the Transeptor Smart Account on the destination chain to execute userOps via a erc-4337 bundler or execute cross-chain token transfer transactions.

## Transfer Token from Transeptor Smart Contract to any destination chain

To transfer a token from a single, universal, first make sure the token is supported by the Chainlink CCIP and your account has a balance of the token or is approved to spend the token.

The externally exposed `ccipSendToken()` function on the Transeptor Smart Contract can be used to transfer tokens from the Transeptor Smart Contract to any destination chain.

To send a token, run the following command:

Where the list of supported chains consists of (case sensitive):

- ethereumSepolia
- optimismGoerli
- arbitrumTestnet
- avalancheFuji
- polygonMumbai

```shell
npx hardhat ccip-smart-account-token-transfer --network <DESTINATION_CHAIN>
```

For example, if you have a Trnanseptor smart account on `optimismGoerli` and you want to send a token to `ethereumSepolia`, run:


```shell
npx hardhat ccip-smart-account-token-transfer 
--network optimismGoerli
--destinationBlockchain ethereumSepolia
--receiver <RECEIVER_ADDRESS_DESTINATION_CHAIN>
--tokenAddress <TOKEN_ADDRESS_SOURCE_CHAIN>
--amount <AMOUNT>
--sender <TRANSEPTOR_SMART_ACCOUNT_ADDRESS_SOURCE_CHAIN>
--isReceiverEoa <true | false>
--pay-fees-in <Native | LINK>
```

## Transfer batch Tokens from Transeptor Smart Contract to any destination chain

To transfer a batch token from a single, universal, first make sure the token is supported by the Chainlink CCIP and your account has a balance of the token or is approved to spend the token.

The externally exposed `ccipSendTokenBatch()` function on the Transeptor Smart Contract can be used to transfer tokens from the Transeptor Smart Contract to any destination chain. It takes the following parameters:
 * @param destinationChainSelector Destination chain selector
 * @param receiver Receiver address. The receiver can be a smart contract or an EAO.
 * @param tokensToSendDetails Array of token details to send
 * @param isEao true if receiver is an EAO
 * @param payFeesIn Pay fees in LINK or native token on source chain
 * @return messageId The ID of the message that was sent.

Example sending batch tokens with messaage with hardhat paying fee in native token:
```ts
const targetChainSelector = 2664363617261496610 // optimismGoerli
const receiver = '0x000000' // receiver address on target chain (optimismGoerli)
const tokensToSendDetails = [
   {
        token: '0x420000',
        amount: '1000000000000000000' // 1 token
   },
   {
        token: '0x420000',
        amount: '1000000000000000000' // 1 token
   
   }
]
const isEao = false
const payFeesIn = 0 // 0 = pay fees in native token, 1 = pay fees in LINK

// create an instance of the Transeptor Smart Contract
const transeptorAccount: TranseptorAccount = TranseptorAccount__factory.connect(basicTokenSenderAddress, signer)

// call the ccipSend function with required parameters
const tx = await transeptorAccount.ccipSendTokenBatch(
    destinationChainSelector,
    receiver,
    tokensToSendDetails,
    isEao,
    payFeesIn
)
        
const receipt = await tx.wait();
console.log(`✅ Message sent, transaction hash: ${tx.hash}`);
```

## Deploy a Basic counter
To deploy an BasicCounter, run the following command:

```shell
npx hardhat deploy-basic-counter --network optimismGoerli --owner <OWNER_ADDRESS> 
```