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
    event Closed(
        uint256 _time,
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

    enum Stages {None, Base, Open, Closed}
    enum Results {Unknown, Bull, Bear, Draw}

    //TODO: remove default values
    Results public result;
    Stages  public stage;

    // address private chainlinkPriceFeed;
    string  public collateralCurrency;
    string  public feedCurrencyPair;

    int256  public initialPrice;
    int256  public finalPrice;
    address public winningToken;

    uint256 public created;
    uint256 public duration;

    uint256 private totalDeposit;
    uint256 private totalRedemption;

    //TODO: maybe it should depends on decimals of the collateral token
    uint    public protocolFee;

    ERC20   public collateralToken;
    ConditionalToken public bullToken;
    ConditionalToken public bearToken;

    // address private oracle;
    // bytes32 private jobId;
    // uint256 private fee;

    // modifier atStage(Stages _stage) {
    //     require(stage == _stage, "Function called in wrong stage");
    //     _;
    // }

    constructor() public {
        stage = Stages.Base;
    }

    //Call the method after clone Market
    function cloneConstructor(
        ERC20 _collateralToken,
        ConditionalToken _bullToken,
        ConditionalToken _bearToken,
        uint256 _duration,
        string memory _collateralCurrency,
        string memory _feedCurrencyPair,
        // address _chainlinkPriceFeed,
        uint _protocolFee
    )
        external
        _logs_
        //_lock_
        // returns (bytes32 requestId)
    {
        require(stage == Stages.None, "Market: This Market is already initialized");
        BPool.cloneConstructor();
        //Get initial price from chainlink
        //     MarketFactory(owner()).getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        collateralToken = _collateralToken;
        bullToken = _bullToken;
        bearToken = _bearToken;

        created = now;
        duration = _duration;

        collateralCurrency = _collateralCurrency;
        feedCurrencyPair = _feedCurrencyPair;
        // chainlinkPriceFeed = _chainlinkPriceFeed;
        protocolFee = _protocolFee;
        stage = Stages.Open;
        // setPublicChainlinkToken();
    }

    function open(int256 _price)
        external
        _logs_
        _lock_
        onlyOwner
    {
        initialPrice = _price;
        // finalize();
    //     require(stage == Clones.Created, "Function called in wrong stage");
    //     require(_tokens.length >= MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");

    //     stage = Stages.Open;
    //     _publicSwap = true;

    //     _mintPoolShare(INIT_POOL_SUPPLY);
    //     _pushPoolShare(msg.sender, INIT_POOL_SUPPLY);
    }


    function close()
        external
        _logs_
        _lock_
        // onlyOwner
    {
        require(stage == Stages.Open, "Market: this market is not open");
        // now > created + duration
        require(
            now > badd(created, duration),
            "Market closing time hasn't yet arrived"
        );
        MarketFactory(_owner).requestFinalPrice();
    }

    //TODO: remove the parameter
    function _close(int256 _price)
        external
        _logs_
        _lock_
        onlyOwner
    {
        //TODO: config the method of Chainlink
        finalPrice = _price;
        //     MarketFactory(owner()).getHistoricalPriceByTimestamp(AggregatorV3Interface(chainlinkPriceFeed), badd(created, duration));

        //TODO: maybe should move it to the method?
        require(finalPrice > 0, "Chainlink error");
        //TODO: require(initialPrice != _finalPrice, "Price didn't change");

        stage = Stages.Closed;

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

        emit Closed(now, finalPrice, result, winningToken);
    }

    //Buy new token pair for collateral token
    function buy(uint256 _amount)
        external
        _logs_
        _lock_
    {
        //TODO: check if now < badd(created, duration)
        require(stage == Stages.Open, "Market: this market is not open");
        require(_amount > 0, "Invalid amount");

        //Get collateral token from sender
        collateralToken.transferFrom(msg.sender, address(this), _amount);

        //Mint conditional tokens to sender
        bullToken.mint(msg.sender, _amount);
        bearToken.mint(msg.sender, _amount);

        //Increase total deposited collateral
        totalDeposit = badd(totalDeposit, _amount);

        //TODO: use the event
        emit Buy(msg.sender, _amount, now);
    }

    function redeem(uint256 _amount)
        external
        _logs_
        _lock_
    {
        require(stage == Stages.Closed, "Market: this market is not closed");
        //TODO: use the protocol fee
        require(_amount > 0, "Invalid amount");
        require(totalDeposit >= badd(totalRedemption, _amount), "No collateral left");

        if (result != Results.Draw) {
            //If there is winner
            //Burn win tokens from a sender
            ConditionalToken(winningToken).burnFrom(msg.sender, _amount);
        } else {
            // if a Draw
            // conditionalToken -= conditionalTokenAllowance / ((bearAllow + bullAllow) / (amount * 2))
            // Get allowance of conditional tokens from the sender
            uint256 _bullAllowance = bullToken.allowance(msg.sender, address(this));
            uint256 _bearAllowance = bearToken.allowance(msg.sender, address(this));
            require(badd(_bullAllowance, _bearAllowance) < bmul(_amount, 2), "Total allowance of conditonal tokens is lower than the given amount");
            // ratio = totalAllowance / conditionalAmount
            uint256 ratio = bdiv(badd(_bullAllowance, _bearAllowance), bmul(_amount, 2));

            // if not 0, burn the tokens
            if (_bullAllowance > 0) {
               bullToken.burnFrom(msg.sender, bdiv(_bullAllowance, ratio));
            }
            if (_bearAllowance > 0) {
                bearToken.burnFrom(msg.sender, bdiv(_bearAllowance, ratio));
            }
        }
        uint _protocolFee = bmul(_amount, protocolFee);

        collateralToken.transfer(msg.sender, bsub(_amount, _protocolFee));
        collateralToken.transfer(_owner, _protocolFee);

        //Increase total redemed collateral
        totalRedemption = badd(totalRedemption, _amount);

        //TODO: use the event
        emit Redeem(msg.sender, _amount, now);
    }
}