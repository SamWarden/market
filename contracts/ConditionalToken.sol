// contracts/ERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./ERC20Burnable.sol";
import "./OwnableClone.sol";

contract ConditionalToken is ERC20Burnable {
    //TODO: is it ok that this has the same name that an event in the MarketFactory?
    event Created(
        string  indexed name,
        string  indexed symbol,
        uint8           decimals,
        uint256         time
    );

    bool private _created;
    //TODO: add lock to base contract with constructor
    constructor() public {
       _created = true;
    }

    function cloneConstructor(string memory name_, string memory symbol_, uint8 decimals_) public {
        require(!_created, "ConditionalToken: this token is already created");
        OwnableClone.cloneConstructor();
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _created = true;

        emit Created(name_, symbol_, decimals_, now);
    }

    function mint(address account, uint256 amount)
        public
        onlyOwner
    {
        _mint(account, amount);
    }
}
