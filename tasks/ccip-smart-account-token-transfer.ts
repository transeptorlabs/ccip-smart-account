import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment, TaskArguments } from "hardhat/types";
import { getPrivateKey, getProviderRpcUrl, getRouterConfig, getPayFeesIn, getLinkTokenAddress } from "./utils";
import { Wallet, providers} from "ethers";
import { IERC20, IERC20__factory, TranseptorAccount, TranseptorAccount__factory } from "../typechain-types";
import { Spinner } from "../utils/spinner";
import { PayFeesIn } from "./constants";

task(`ccip-smart-account-token-transfer`, `Transfers tokens from one blockchain to another using Chainlink CCI from a smart account`)
    .addParam(`destinationBlockchain`, `The name of the destination blockchain (for example polygonMumbai)`)
    .addParam(`receiver`, `The address of the receiver account on the destination blockchain`)
    .addParam(`tokenAddress`, `The address of a token to be sent on the source blockchain`)
    .addParam(`sender`, `The address of the Transeptor.sol smart account on the source blockchain`)
    .addParam(`amount`, `The amount of token to be sent`)
    .addParam(`isReceiverEoa`, `If the receiver is an EOA or a smart account`)
    .addOptionalParam(`router`, `The address of the Router contract`)
    .addParam(`payFeesIn`, `Choose between 'Native' and 'LINK'`)
    .setAction(async (taskArguments: TaskArguments, hre: HardhatRuntimeEnvironment) => {
        const {destinationBlockchain, receiver, tokenAddress, sender, payFeesIn, amount, isReceiverEoa } = taskArguments;
        const sourceBlockchain = hre.network.name;
        const spinner: Spinner = new Spinner();
        const destinationChainSelector = getRouterConfig(destinationBlockchain).chainSelector;
        const fee = getPayFeesIn(payFeesIn);
        const linkAddress = getLinkTokenAddress(sourceBlockchain);

        if (sourceBlockchain !== 'ethereumSepolia') {
            throw new Error("This task can only be executed on the ethereumSepolia network");
        }

        if (destinationBlockchain === sourceBlockchain) {
            throw new Error("The destination blockchain cannot be the same as the source blockchain");
        }

        // get signer eao(should be owner of the TranseptorAccount on the destination chain)
        const privateKey = getPrivateKey();
        const sourceRpcProviderUrl = getProviderRpcUrl(sourceBlockchain);

        const provider = new providers.JsonRpcProvider(sourceRpcProviderUrl);
        const wallet = new Wallet(privateKey);
        const signer = wallet.connect(provider);

        // create an instance of the Transeptor Smart Contract
        const transeptorAccount: TranseptorAccount = TranseptorAccount__factory.connect(sender, signer)

        // make sure that the signer is the owner of the TranseptorAccount
        const owner = await transeptorAccount.owner();
        if (owner.toLowerCase() !== signer.address.toLowerCase()) {
            throw new Error(`The signer ${signer.address} is not the owner of the TranseptorAccount ${sender}`);
        }

        // check if the token is supported
        const supportedTokens = await transeptorAccount.getSupportedTokens(
            destinationChainSelector
        );

        if (!supportedTokens.includes(tokenAddress)) {
            throw new Error(`The token ${tokenAddress} is not supported on the destination blockchain ${destinationBlockchain}`);
        }

        // get ccip fees and check if the transeptor account has enough balance to pay for the fees
        console.log(`ℹ️  Calculating CCIP fees...`);
        spinner.start();
        const ccipFee = await transeptorAccount.getCcipTokenTransferFee(
            destinationChainSelector,
            receiver,
            tokenAddress,
            amount,
            isReceiverEoa,
            fee
        );
        spinner.stop();
        
        if (fee === PayFeesIn.LINK) {
            console.log(`ℹ️  Estimated fees (juels): ${ccipFee}`);
            const feeToken: IERC20 = IERC20__factory.connect(linkAddress, signer);
            const balance = await feeToken.balanceOf(sender);
            if (balance.lt(ccipFee)) {
                throw new Error(`The TranseptorAccount ${sender} does not have enough LINK balance to pay for the CCIP fees`);
            }
        } else {
            console.log(`ℹ️  Estimated fees (wei): ${ccipFee}`);
            const balance = await provider.getBalance(sender);
            if (balance.lt(ccipFee)) {
                throw new Error(`The TranseptorAccount ${sender} does not have enough ETH balance to pay for the CCIP fees`);
            }
        }

        // send CCIP token transfer message by calling ccipSendToken on smart account
        console.log(`ℹ️  Attempting to transfer token ${tokenAddress} from ${sourceBlockchain} to ${destinationBlockchain}. Sender: ${sender}, Receiver: ${receiver}`);
        spinner.start();

        const tx = await transeptorAccount.ccipSendToken(
            destinationChainSelector,
            receiver,
            tokenAddress,
            amount,
            isReceiverEoa,
            fee
        )

        await tx.wait();

        spinner.stop();
        console.log(`✅ Message sent, transaction hash: ${tx.hash}`);
    });

// TODO: Also allowing transfer as a userOp, since the ccipSendToken can be called by the owner and the entrypint contract
