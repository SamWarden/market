// contracts/ERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ConditionalToken is ERC20, Ownable {

    constructor() public {
        _owner = msg.sender;
    }

    function mint(address account, uint256 amount)
        public
        onlyOwner
    {
        _mint(account, amount)
    }
}
