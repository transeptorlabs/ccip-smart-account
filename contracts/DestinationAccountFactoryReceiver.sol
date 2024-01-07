// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import { CCIPReceiver } from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { TranseptorAccountFactory } from "./TranseptorAccountFactory.sol";

/**
 * A CCIPReceiver contract that allows crosschain smart account creation.
 */
contract DestinationAccountFactoryReceiver is CCIPReceiver, Ownable {
    TranseptorAccountFactory accountFactory;

    event CreateCallSuccessfull();

    constructor(address router, address accountFactoryAddress) CCIPReceiver(router) {
        accountFactory = TranseptorAccountFactory(accountFactoryAddress);
    }

    /**
     * @dev Sets the account factory address.
     * @param accountFactoryAddress Account factory address
     */
    function setAccountFactory(address accountFactoryAddress) external onlyOwner {
        accountFactory = TranseptorAccountFactory(accountFactoryAddress);
    }


    /**
     * @dev Returns the account factory address.
     */
    function getAccountFactory() external view returns (address) {
        return address(accountFactory);
    }

    /* ******************************************************
     * Internal functions
     * ******************************************************
    */

    /**
     * @dev CCIPReceiver callback function will be called when a CCIP message is received to deploy a new smart account.
     * @param message CCIP message
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        (bool success, ) = address(accountFactory).call(message.data);
        require(success);
        emit CreateCallSuccessfull();
    }
}