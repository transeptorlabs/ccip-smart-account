// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import { CCIPReceiver } from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { TranseptorAccountFactory } from "./TranseptorAccountFactory.sol";

/**
 * A CCIPReceiver contract that allows crosschain Transeptor smart account creation.
 */
contract DestinationAccountFactoryReceiver is CCIPReceiver, Ownable {
    TranseptorAccountFactory accountFactory;

    event CreateCallSuccessfull();

    constructor(address router, address accountFactoryAddress) CCIPReceiver(router) {
        accountFactory = TranseptorAccountFactory(accountFactoryAddress);
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        (bool success, ) = address(accountFactory).call(message.data);
        require(success);
        emit CreateCallSuccessfull();
    }
}