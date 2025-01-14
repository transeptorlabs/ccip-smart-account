// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./TranseptorAccount.sol";

/**
 * A sample factory contract for TranseptorAccount that has Chainlink's CCIP support.
 * A UserOperations "initCode" holds the address of the factory, and a method call (to createAccount, in this sample factory).
 * The factory's createAccount returns the target account address even if it is already installed.
 * This way, the entryPoint.getSenderAddress() can be called either before or after the account is created.
 */
contract TranseptorAccountFactory {
    TranseptorAccount public immutable accountImplementation;

    /**
    * @dev Constructor that sets the address of the entry point and ccip router on source chain
    * @param entryPoint Address of the entry point on source chain
    * @param router Address of the router on source chain
    * @param link Address of the LINK token on source chain
    */
    constructor(IEntryPoint entryPoint, address router, address link) {
        accountImplementation = new TranseptorAccount(entryPoint, router, link);
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(address owner,uint256 salt) public returns (TranseptorAccount ret) {
        address addr = getAddress(owner, salt);
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            return TranseptorAccount(payable(addr));
        }
        ret = TranseptorAccount(payable(new ERC1967Proxy{salt : bytes32(salt)}(
                address(accountImplementation),
                abi.encodeCall(TranseptorAccount.initialize, (owner))
            )));
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     */
    function getAddress(address owner,uint256 salt) public view returns (address) {
        return Create2.computeAddress(bytes32(salt), keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    address(accountImplementation),
                    abi.encodeCall(TranseptorAccount.initialize, (owner))
                )
            )));
    }
}