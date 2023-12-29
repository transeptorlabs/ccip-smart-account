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

To deploy a cross-chain transeptor smart account, run the following command:

```shell  
npx hardhat ccip-smart-account-deploy
--factory <accountFactoryAddress> # Optional
```