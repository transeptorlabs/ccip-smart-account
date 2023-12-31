# Transeptor CCIP ERC4337 Smart Account documentation

> **Note**
>
> _The project in active development. The documentation is not complete and some of the features are not implemented yet._
>

ccip supported networks: https://docs.chain.link/ccip/supported-networks#overview

## Billing and gaslimit

- billing: https://docs.chain.link/ccip/billing
- gaslimit: The gasLimit specifies the maximum amount of gas CCIP can consume to execute `ccipReceive()` on the contract located on the `destination blockchain`. Read more about gasLimit best practices [here](https://docs.chain.link/ccip/best-practices#setting-gaslimit) (**Unspent gas is not refunded.**).

## Deploy Account Factory

To deploy an account factory, run the following command:

```shell
npx hardhat deploy-account-factory
--router <routerAddress> # Optional
--entrypoint <entrypointAddress> # Optional
```

For example, if you want to deploy an account factory to ethereumSepolia you need to deploy this contract on ethereumSepolia, by running:

```shell
npx hardhat deploy-account-factory --network ethereumSepolia
```

Optionally, you can pass the address of the Chainlink CCIP `Router.sol` smart contract or `EntryPoint.sol` on the optimismGoerli blockchain as a constructor argument. To do so, run the following command:

```shell
npx hardhat deploy-account-factory --network optimismGoerli --router <ROUTER_ADDRESS> --entrypoint <ENTRYPOINT_ADDRESS>
```

## Cross-chain Transeptor Smart account deployment
<!-- TODO: -->
To deploy a cross-chain transeptor smart account, run the following command:

```shell  
npx hardhat ccip-smart-account-deploy
--factory <accountFactoryAddress> # Optional
```

## Transfer Token(s) with message from Transeptor Smart Contract to any destination chain

To transfer a token or batch of tokens from a single, universal, first make sure the token is supported by the Chainlink CCIP and your account has a balance of the token or is approved to spend the token.

The externally exposed `ccipSendMessage()` function on the Transeptor Smart Contract can be used to transfer tokens from the Transeptor Smart Contract to any destination chain. It takes the following parameters:
- @param destinationChainSelector Destination chain selector
- @param receiver Receiver address
- @param message The string message to be sent.
- @param token token address.
- @param amount token amount.
- @param payFeesIn Pay fees in LINK or native token on source chain
- @return messageId The ID of the message that was sent.

Example sending token with messaage with hardhat paying fee in native token:
```ts
const targetChainSelector = 2664363617261496610 // optimismGoerli
const receiver = '0x000000' // receiver address on target chain (optimismGoerli)
const tokenAddress = '0x420000'
const amount = '1000000000000000000' // 1 token
const message = 'Hello World'
const payFeesIn = 0 // 0 = pay fees in native token, 1 = pay fees in LINK

// create an instance of the Transeptor Smart Contract
const transeptorAccount: TranseptorAccount = TranseptorAccount__factory.connect(basicTokenSenderAddress, signer)

// call the ccipSend function with required parameters
const tx = await transeptorAccount.ccipSendMessage(
    destinationChainSelector,
    receiver,
    message,
    tokenAddress,
    amount,
    payFeesIn
)
        
const receipt = await tx.wait();
console.log(`✅ Message sent, transaction hash: ${tx.hash}`);
```