// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract BasicCounter is Ownable {
    uint256 public count = 0;

    function setCount(uint256 newCount) public {
        count = newCount;
    }

    function increment() public onlyOwner {
        count++;
    }
}