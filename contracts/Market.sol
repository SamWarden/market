// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./balancer/BPool.sol";
import "./ConditionalToken.sol";

contract Market is Ownable {
    //TODO: add more info to events
    event Created(uint256 indexed marketID, uint256 _time);
    event Paused(uint256 indexed marketID, uint256 _time);
    event Resumed(uint256 indexed marketID, uint256 _time);
    event Closed(uint256 indexed marketID, uint256 _time);
    event Buy(uint256 indexed marketID, uint256 _time);
    event Redeem(uint256 indexed marketID, uint256 _time);
    event NewBearToken(address indexed contractAddress, uint256 _time);
    event NewBullToken(address indexed contractAddress, uint256 _time);

    enum Status {Running, Paused, Closed}

    struct MarketStruct {
        bool exist;
        Status status;
        uint256 marketID;
        uint256 baseCurrencyID;
        int256 initialPrice;
        int256 finalPrice;
        uint256 created;
        uint256 duration;
        uint256 totalDeposit;
        uint256 totalRedemption;
        address collateralToken;
        address bearToken;
        address bullToken;
        BPool pool;
    }

    mapping(uint256 => MarketStruct) public markets;
    mapping(uint256 => address) public baseCurrencyToChainlinkFeed;

    //Variables
    uint256 public currentMarketID = 1;

    AggregatorV3Interface internal priceFeed;
    BFactory factory;

    //Constants
    uint256 public constant CONDITIONAL_TOKEN_WEIGHT = 10 * factory.BONE;
    uint256 public constant COLLATERAL_TOKEN_WEIGHT  = CONDITIONAL_TOKEN_WEIGHT * 2;

    constructor(address _factory) public {
        factory = BFactory(_factory)
        baseCurrencyToChainlinkFeed[
            uint256(1)
        ] = 0x9326BFA02ADD2366b30bacB125260Af641031331; //Network: Kovan Aggregator: ETH/USD
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice(AggregatorV3Interface feed)
        public
        view
        returns (int256)
    {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        return price;
    }

    /**
     * Returns historical price for a round id.
     * roundId is NOT incremental. Not all roundIds are valid.
     * You must know a valid roundId before consuming historical data.
     *
     * ROUNDID VALUES:
     *    InValid:      18446744073709562300
     *    Valid:        18446744073709562301
     *
     * @dev A timestamp with zero value means the round is not complete and should not be used.
     */
    function getHistoricalPrice(AggregatorV3Interface feed, uint80 roundId)
        public
        view
        returns (int256)
    {
        (
            uint80 id,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = feed.getRoundData(roundId);
        require(timeStamp > 0, "Round not complete");
        return price;
    }

    function cloneBearToken(uint8 _decimals) internal returns (ConditionalToken) {
        ConditionalToken bearToken = new ConditionalToken("Bear", "Bear", _decimals);
        emit NewBearToken(address(bearToken), now);
        // bearToken.setController(msg.sender);
        return bearToken;
    }

    function cloneBullToken(uint8 _decimals) internal returns (ConditionalToken) {
        ConditionalToken bullToken = new ConditionalToken("Bull", "Bull", _decimals);
        emit NewBullToken(address(bullToken), now);
        return bullToken;
    }

    function addConditionalToken(BPool _pool, ConditionalToken _conditionalToken, uint256 _conditionalBalance)
        internal
    {
        //Mint bear and bull tokens
        _conditionalToken.mint(address(this), _conditionalBalance);

        addToken(_pool, _conditionalToken, _conditionalBalance, CONDITIONAL_TOKEN_WEIGHT);
    }

    function addCollateralToken(BPool _pool, IERC20 _collateralToken, uint256 _collateralBalance)
        internal
    {
        //Pull collateral tokens from sender
        //TODO: try to make the transfer to the pool directly
        _collateralToken.transferFrom(msg.sender, address(this), _collateralBalance);

        addToken(_pool, _collateralToken, _collateralBalance, COLLATERAL_TOKEN_WEIGHT);
    }

    function addToken(BPool _pool, IERC20 token, uint256 balance, uint256 denorm)
        internal
    {
        //Approve pool
        token.approve(address(_pool), balance);

        //Add token to the pool
        _pool.bind(address(token), balance, denorm);
    }

    function create(address _collateralToken, uint256 _baseCurrencyID, uint256 _duration)
        public
    {
        //TODO: check if _collateralToken is a valid ERC20 contract
        require(
            baseCurrencyToChainlinkFeed[_baseCurrencyID] != address(0),
            "Invalid base currency"
        );
        require(
            _duration >= 600 seconds && _duration < 365 days,
            "Invalid duration"
        );

        uint8 _collateralDecimals = IERC20(_collateralToken).decimals();

        //Estamate balance tokens
        //TODO: ask about initial balance
        uint256 _initialBalance = 1000;
        uint256 _collateralBalance = _initialBalance * _collateralDecimals;
        uint256 _conditionalBalance = _collateralBalance / 2;

        //Calculate swap fee
        //TODO: correct the calculation
        uint256 _swapFee = calcSwapFee(_collateralDecimals);

        //Create a pool of the balancer
        //TODO: add clone-factory to the factory
        BPool _pool = factory.newBPool();

        //Contract factory (clone) for two ERC20 tokens
        ConditionalToken _bearToken = cloneBearToken(_collateralDecimals);
        ConditionalToken _bullToken = cloneBullToken(_collateralDecimals);

        //Add conditional and collateral tokens to the pool
        addConditionalToken(_pool, _bearToken, _conditionalBalance);
        addConditionalToken(_pool, _bullToken, _conditionalBalance);
        addCollateralToken(_pool, IERC20(_collateralToken), _collateralBalance);

        //Set the swap fee
        _pool.setSwapFee(_swapFee)

        //Release the pool and allow public swaps
        _pool.release();

        //Get chainlink price feed by _baseCurrencyID
        address _chainlinkPriceFeed =
            baseCurrencyToChainlinkFeed[_baseCurrencyID];

        int256 _initialPrice =
            getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        require(_initialPrice > 0, "Chainlink error");

        MarketStruct memory marketStruct =
            MarketStruct({
                exist: true,
                status: Status.Running,
                marketID: currentMarketID,
                baseCurrencyID: _baseCurrencyID,
                initialPrice: _initialPrice,
                finalPrice: 0,
                created: now,
                duration: _duration,
                totalDeposit: 0,
                totalRedemption: 0,
                collateralToken: _collateralToken,
                bearToken: address(_bearToken),
                bullToken: address(_bullToken),
                pool: address(_pool),
            });

        markets[currentMarketID] = marketStruct;

        emit Created(currentMarketID, now);

        //Increment current market ID
        currentMarketID++;
    }

    function calcSwapFee(uint8 _decimals) public returns (uint8) {
        //TODO: correct the calculation
        return _decimals / 1000 * 3; // 0.3%
    }

    function close(uint256 _marketID) public {
        require(markets[_marketID].exist, "Market doesn't exist");
        require(
            markets[_marketID].status != Status.Closed,
            "Market has already been closed"
        );
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
    function buy(uint256 _marketID, uint256 _amount) external {
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

    function redeem(uint256 _marketID, uint256 _amount) external {
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

    function setBaseCurrencyToChainlinkFeed(
        uint256 _baseCurrencyID,
        address _chainlinkFeed
    ) public onlyOwner {
        baseCurrencyToChainlinkFeed[_baseCurrencyID] = _chainlinkFeed;
    }

    function viewMarketExist(uint256 _marketID) public view returns (bool) {
        return markets[_marketID].exist;
    }
}
