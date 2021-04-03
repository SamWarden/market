// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./balancer/BPool.sol";
import "./ConditionalToken.sol";
import "./MarketFactory.sol";

contract Market is BPool {
    using SafeMath for uint256;
    using SafeMath for uint8;

    enum Stages {Created, Open, Closed}
    enum Results {Unknown, Bull, Bear}

    Results result = Results.Unknown;
    Stages stage = Stages.Created;

    address chainlinkPriceFeed;
    string collateralCurrency;
    string feedCurrencyPair;

    int256 initialPrice;
    int256 finalPrice;
    address winningToken;

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

    //Call the method after clone Market
    function cloneConstructor(
        IERC20 _collateralToken,
        ConditionalToken _bearToken,
        ConditionalToken _bullToken,
        uint256 _duration,
        string memory _collateralCurrency,
        string memory _feedCurrencyPair,
        address _chainlinkPriceFeed
    )
        external
        _logs_
        //_lock_
        atStage(Stages.Created)
    {
        //Get initial price from chainlink
        // int256 _initialPrice =
        //     MarketFactory(owner()).getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        // require(_initialPrice > 0, "Chainlink error");

        collateralToken = _collateralToken;
        bearToken = _bearToken;
        bullToken = _bullToken;

        created = now;
        duration = _duration;
        // initialPrice = _initialPrice;

        collateralCurrency = _collateralCurrency;
        feedCurrencyPair = _feedCurrencyPair;
        chainlinkPriceFeed = _chainlinkPriceFeed;

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
        // now > created + duration
        require(
            now > created.add(duration),
            "Market closing time hasn't yet arrived"
        );

        //TODO: config the method of Chainlink
        finalPrice = MarketFactory(owner()).getHistoricalPriceByTimestamp(AggregatorV3Interface(chainlinkPriceFeed), created.add(duration));

        //TODO: maybe should move it to the method?
        require(finalPrice > 0, "Chainlink error");
        //TODO: require(initialPrice != _finalPrice, "Price didn't change");

        stage = Stages.Closed;

        //TODO: add draw
        if (finalPrice > initialPrice) {
            winningToken = address(bullToken);
            result = Results.Bull;
        } else {
            winningToken = address(bearToken);
            result = Results.Bear;
        }

        // emit Closed(finalPrice, now);
    }

    //Buy new token pair for collateral token
    function buy(uint256 _amount)
        external
        _logs_
        _lock_
        atStage(Stages.Open)
    {
        require(_amount > 0, "Invalid amount");

        //Get collateral token from sender
        collateralToken.transferFrom(msg.sender, address(this), _amount);

        //Mint conditional tokens to sender
        bullToken.mint(msg.sender, _amount);
        bearToken.mint(msg.sender, _amount);

        //Increase total deposited collateral
        totalDeposit = totalDeposit.add(_amount);

        // emit Buy(msg.sender, _amount, now);
    }

    function redeem(uint256 _amount)
        external
        _logs_
        _lock_
        atStage(Stages.Closed)
    {
        require(_amount > 0, "Invalid amount");
        require(totalDeposit >= totalRedemption.add(_amount), "No collateral left");

        //Get win tokens from sender
        ConditionalToken(winningToken).transferFrom(msg.sender, address(this), _amount);

        //Send collateral tokens to sender
        collateralToken.transfer(msg.sender, _amount);

        //Increase total redemed collateral
        totalRedemption = totalRedemption.add(_amount);

        // emit Redeem(_marketID, now);
    }
}