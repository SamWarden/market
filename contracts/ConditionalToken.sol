// contracts/ERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ConditionalToken is ERC20, Ownable {
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) public {}

    function cloneConstructor(uint8 decimals_) public {
        _decimals = decimals_;
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
