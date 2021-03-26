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
        _;
    }

    constructor() public {}

    function cloneConstructor () public onlyOwner atStage(Stages.Created) {

        stage = Stages.Open;
    }

    function getStage() public view returns (Stages) {
        return stage;
    }

    function close(uint256 _marketID) public atStage(Stages.Open) {
        require(
            SafeMath.add(
                markets[_marketID].created,
                markets[_marketID].duration
            ) > now,
            "Market closing time hasn't yet arrived"
        );

        //Get chainlink price feed by _baseCurrencyID
        address _chainlinkPriceFeed =
            baseCurrencyToChainlinkFeed[markets[_marketID].baseCurrencyID];

        //TODO: query chainlink by valid timestamp
        int256 _finalPrice =
            getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        require(_finalPrice > 0, "Chainlink error");
        //TODO: require(markets[_marketID].initialPrice != _finalPrice, "Price didn't change");

        markets[_marketID].status = Status.Closed;
        markets[_marketID].finalPrice = _finalPrice;

        emit Closed(_marketID, now);
    }

    //Buy new token pair for collateral token
    function buy(uint256 _marketID, uint256 _amount) external atStage(Stages.Open) {
        require(markets[_marketID].exist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Running, "Invalid status");
        require(_amount > 0, "Invalid amount");

        //TODO: deposit collateral in accordance to markeetid collateral. require(token.transferFrom(msg.sender, this, _amount));
        //TODO: mint both tokens. _mint(msg.sender, supply);
        //TODO: approve both tokens
        //TODO: send both tokens to user. require(token.transferFrom(msg.sender, this, _amount));

        //Increase total deposited collateral
        markets[_marketID].totalDeposit = SafeMath.add(
            markets[_marketID].totalDeposit,
            _amount
        );

        emit Buy(_marketID, now);
    }

    function redeem(uint256 _marketID, uint256 _amount) external atStage(Stages.Open) {
        require(markets[_marketID].exist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Closed, "Invalid status");
        require(_amount > 0, "Invalid amount");
        require(
            markets[_marketID].totalDeposit >
                markets[_marketID].totalRedemption,
            "No collateral left"
        );

        //Determine winning token address
        address winningToken;

        if (markets[_marketID].finalPrice > markets[_marketID].initialPrice) {
            winningToken = markets[_marketID].bearToken;
        } else {
            winningToken = markets[_marketID].bullToken;
        }

        //TODO: deposit winningToken _amount. require(token.transferFrom(msg.sender, this, _amount));
        //TODO: send collateral to user in accordance to markeetid collateral. 1 token = 1 collateral

        //Increase total redemed collateral
        markets[_marketID].totalRedemption = SafeMath.add(
            markets[_marketID].totalRedemption,
            _amount
        );

        emit Redeem(_marketID, now);
    }
}