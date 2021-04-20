// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";
import "./ERC20.sol";
import "./OwnableClone.sol";
import "./balancer/BPool.sol";
import "./ConditionalToken.sol";
import "./MarketFactory.sol";

contract Market is BPool {
    event Open(
        uint256 time,
        int256  initialPrice
    );

    event Closed(
        uint256 time,
        int256  finalPrice,
        Results result,
        address winningToken
    );

    event Buy(
        address indexed sender,
        uint256 indexed amount,
        uint256         time
    );

    event Redeem(
        address indexed sender,
        uint256 indexed amount,
        uint256         time
    );

    enum Stages {None, Base, Initialized, Open, Closed}
    enum Results {Unknown, Draw, Bull, Bear}

    //TODO: remove default values
    Results public result;
    Stages  public stage;

    // address private chainlinkPriceFeed;
    string  public baseCurrency;
    string  public collateralCurrency;

    int256  public initialPrice;
    int256  public finalPrice;
    address public winningToken;

    uint256 public created;
    uint256 public duration;

    uint256 public totalDeposit;
    uint256 public totalRedemption;

    //TODO: maybe it should depends on decimals of the collateral token
    uint    public protocolFee;

    ERC20   public collateralToken;
    ConditionalToken public bullToken;
    ConditionalToken public bearToken;

    constructor() public {
        stage = Stages.Base;
    }

    //Call the method after clone Market
    function cloneConstructor(
        ERC20 _collateralToken,
        ConditionalToken _bullToken,
        ConditionalToken _bearToken,
        uint256 _duration,
        string memory _baseCurrency,
        string memory _collateralCurrency,
        uint _protocolFee
    )
        external
        _logs_
        //_lock_
    {
        require(stage == Stages.None, "Market: this Market is already initialized");
        BPool.cloneConstructor();

        collateralToken = _collateralToken;
        bullToken = _bullToken;
        bearToken = _bearToken;

        created = now;
        duration = _duration;

        baseCurrency = _baseCurrency;
        collateralCurrency = _collateralCurrency;
        protocolFee = _protocolFee;

        stage = Stages.Initialized;
    }

    function open(int256 _price)
        external
        _logs_
        _lock_
        onlyOwner
    {
        require(stage == Stages.Initialized, "Market: this market is not initialized");
        initialPrice = _price;
        stage = Stages.Open;
        _finalized = true;
        _publicSwap = true;

        emit Open(now, initialPrice);
    }

    function close()
        external
        _logs_
        _lock_
    {
        require(stage == Stages.Open, "Market: this market is not open");
        // if now > created + duration
        require(
            now > SafeMath.add(created, duration),
            "Market: market closing time hasn't yet arrived"
        );
        MarketFactory(_owner).requestFinalPrice();
    }

    function _close(int256 _price)
        external
        _logs_
        _lock_
        onlyOwner
    {
        require(stage == Stages.Open, "Market: this market is not open");
        finalPrice = _price;

        //TODO: add draw
        if (finalPrice > initialPrice) {
            winningToken = address(bullToken);
            result = Results.Bull;
        } else if (finalPrice < initialPrice) {
            winningToken = address(bearToken);
            result = Results.Bear;
        } else {
            result = Results.Draw;
        }
        stage = Stages.Closed;

        emit Closed(now, finalPrice, result, winningToken);
    }

    //Buy conditional tokens for collateral token
    function buy(uint256 _amount)
        external
        _logs_
        _lock_
    {
        //TODO: check if now < created + duration
        require(stage == Stages.Open || (stage == Stages.Initialized && msg.sender == _owner), "Market: this market is not open");
        require(_amount > 0, "Market: amount has to be greater than 0");

        //Get collateral token from sender
        collateralToken.transferFrom(msg.sender, address(this), _amount);

        //Mint conditional tokens to sender
        bullToken.mint(msg.sender, _amount);
        bearToken.mint(msg.sender, _amount);

        //Increase total deposited collateral
        totalDeposit = SafeMath.add(totalDeposit, _amount);

        emit Buy(msg.sender, _amount, now);
    }

    function redeem(uint256 _tokenAmountIn)
        external
        _logs_
        _lock_
    {
        require(stage == Stages.Closed, "Market: this market is not closed");
        //TODO: check too small redeem
        require(_tokenAmountIn > 0, "Market: tokenAmountIn has to be greater than 0");

        uint256 _tokenAmountOut;

        if (result != Results.Draw) {
            //If there is winner
            //Burn win tokens from a sender
            ConditionalToken(winningToken).burnFrom(msg.sender, _tokenAmountIn);
            _tokenAmountOut = _tokenAmountIn;
        } else {
            // if a Draw
            // conditionalToken -= conditionalTokenAllowance / ((bearAllow + bullAllow) / amount)
            // Get allowance of conditional tokens from the sender
            uint256 _bullAllowance = bullToken.allowance(msg.sender, address(this));
            uint256 _bearAllowance = bearToken.allowance(msg.sender, address(this));
            require(SafeMath.add(_bullAllowance, _bearAllowance) >= _tokenAmountIn, "Market: total allowance of conditonal tokens is lower than the given amount");
            // ratio = (bullAllowance + bearAllowance) / tokenAmountIn
            uint256 ratio = SafeMath.div(SafeMath.add(_bullAllowance, _bearAllowance), _tokenAmountIn);

            // if not 0, burn the tokens
            if (_bullAllowance > 0) {
               bullToken.burnFrom(msg.sender, SafeMath.div(_bullAllowance, ratio));
            }
            if (_bearAllowance > 0) {
                bearToken.burnFrom(msg.sender, SafeMath.div(_bearAllowance, ratio));
            }
            // AO = AI * 0.5
            _tokenAmountOut = SafeMath.div(_tokenAmountIn, 2);
        }

        require(totalDeposit >= SafeMath.add(totalRedemption, _tokenAmountOut), "Market: no collateral left");

        // bmul: (AO * pf + (BONE / 2)) / BONE
        uint _protocolFee = bmul(_tokenAmountOut, protocolFee);

        collateralToken.transfer(msg.sender, SafeMath.sub(_tokenAmountOut, _protocolFee));
        collateralToken.transfer(_owner, _protocolFee);
        // collateralToken.transfer(msg.sender, _tokenAmountOut);

        //Increase total redemed collateral
        totalRedemption = SafeMath.add(totalRedemption, _tokenAmountOut);

        //TODO: use the event
        emit Redeem(msg.sender, _tokenAmountOut, now);
    }
}