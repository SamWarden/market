// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./balancer/BPool.sol";
import "./ConditionalToken.sol";

contract Market is BPool, Ownable {
    enum Status {Created, Open, Closed}

    Status status = Status.Created;

    constructor() public {}

    function cloneConstructor () public onlyOwner {
        require(status == status.Created, "Status has to be Created");

        status = Status.Open
    }

    function getStatus() public view returns (Status) {
        return status;
    }
}