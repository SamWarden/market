// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
import "@openzeppelin/contracts/access/Ownable.sol";

contract ContChild is Ownable {}
contract ContParrent {
  address public child;

  constructor() public {
    child = address(new ContChild());
  }
}
