// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./balancer/BPool.sol";
import "./ConditionalToken.sol";

contract Market is BPool {
    using SafeMath for uint256, uint8;

    enum Stages {Created, Open, Closed}
    enum Results {Unknown, Bull, Bear}

    Results result = Results.Unknown;
    Stages stage = Stages.Created;

    address winningToken;
    uint256 collateralCurrency;
    address chainlinkPriceFeed;
    int256 initialPrice;
    int256 finalPrice;
    uint256 created;
    uint256 duration;

    uint256 totalDeposit;
    uint256 totalRedemption;

    IERC20 collateralToken;
    ConditionalToken bearToken;
    ConditionalToken bullToken;

    modifier atStage(Stages _stage) {
        require(stage == _stage, "Function called in wrong stage");
        _;
    }

    // constructor() public {}

    function cloneConstructor()
        external
        _logs_
        //_lock_
        onlyOwner
        atStage(Stages.Created)
    {
        collateralCurrency = _collateralCurrency;
        initialPrice = _initialPrice;
        duration = _duration;
        collateralToken = _collateralToken;
        bearToken = _bearToken;
        bullToken = _bullToken;
        finalPrice = 0;
        created = now;
        totalRedemption = 0;

        stage = Stages.Open;
    }

    function getStage()
        public view
        _viewlock_
        returns (Stages)
    {
        return stage;
    }

    function close()
        public
        _logs_
        _lock_
        atStage(Stages.Open)
    {
        require(
            created.add(duration) < now,
            "Market closing time hasn't yet arrived"
        );

        //Get chainlink price feed by _collateralCurrency
        // address _chainlinkPriceFeed =
        //     baseCurrencyToChainlinkFeed[collateralCurrency];

        //TODO: query chainlink by valid timestamp
        finalPrice = getLatestPrice(AggregatorV3Interface(chainlinkPriceFeed));

        require(finalPrice > 0, "Chainlink error");
        //TODO: require(initialPrice != _finalPrice, "Price didn't change");

        stage = Stages.Closed;

        if (finalPrice > initialPrice) {
            winningToken = address(bullToken);
            result = Results.Bull;
        } else {
            winningToken = address(bearToken);
            result = Results.Bear;
        }

        emit Closed(finalPrice, now);
    }

    //Buy new token pair for collateral token
    function buy(uint256 _amount)
        external
        _logs_
        _lock_
        atStage(Stages.Open)
    {
        require(_amount > 0, "Invalid amount");


        collateralToken.transferFrom(msg.sender, address(this), _amount);

        bullToken.mint(msg.sender, _amount);
        bearToken.mint(msg.sender, _amount);

        //Increase total deposited collateral
        totalDeposit = totalDeposit.add(_amount);

        emit Buy(msg.sender, _amount, now);
    }

    function redeem(uint256 _amount)
        external
        _logs_
        _lock_
        atStage(Stages.Closed)
    {
        require(_amount > 0, "Invalid amount");
        require(totalDeposit > totalRedemption,
            "No collateral left"
        );

        //TODO: deposit winningToken _amount. require(token.transferFrom(msg.sender, this, _amount));
        //TODO: send collateral to user in accordance to markeetid collateral. 1 token = 1 collateral

        //Increase total redemed collateral
        totalRedemption = totalRedemption.add(_amount);

        emit Redeem(_marketID, now);
    }
}