// contracts/ERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Ownable.sol";

contract ConditionalToken is ERC20, Ownable {
    uint8 private _decimals;

    function cloneConstructor(uint8 decimals_, string memory name_, string memory symbol_) public {
        Ownable.cloneConstructor();
        _decimals = decimals_;
        _name = name_;
        _symbol = symbol_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount)
        public
        onlyOwner
    {
        _mint(account, amount);
    }
}
