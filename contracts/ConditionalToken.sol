// contracts/ERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./ERC20Burnable.sol";
import "./OwnableClone.sol";

//TODO: maybe use the Burnable ERC20
contract ConditionalToken is ERC20Burnable {
    function cloneConstructor(string memory name_, string memory symbol_, uint8 decimals_) public {
        OwnableClone.cloneConstructor();
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function mint(address account, uint256 amount)
        public
        onlyOwner
    {
        _mint(account, amount);
    }
}
