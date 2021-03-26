// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./balancer/BPool.sol";
import "./ConditionalToken.sol";

contract Market is BPool, Ownable {
    enum Stages {Created, Open, Closed}

    Stages stage = Stages.Created;

    modifier atStage(Stages _stage) {
        require(stage == _stage, "Function called in wrong stage");
    }

    constructor() public {}

    function cloneConstructor () public onlyOwner atStage(Stages.Created) {

        stage = Stages.Open;
    }

    function getStage() public view returns (Stages) {
        return stage;
    }
}