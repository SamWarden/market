// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./balancer/BPool.sol";
import "./balancer/BFactory.sol";
import "./ConditionalToken.sol";

contract MarketFactory is Ownable {
    using SafeMath for uint256, uint8;

    //TODO: add more info to events
    event Created(uint256 indexed marketID, uint256 _time);
    event Resumed(uint256 indexed marketID, uint256 _time);
    event Closed(uint256 indexed marketID, uint256 _time);
    event Buy(uint256 indexed marketID, uint256 _time);
    event Redeem(uint256 indexed marketID, uint256 _time);
    event NewBearToken(address indexed contractAddress, uint256 _time);
    event NewBullToken(address indexed contractAddress, uint256 _time);

    struct MarketStruct {
        bool exist;
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
    BFactory private factory;

    address private baseBearToken;
    address private baseBullToken;

    //Constants
    uint256 public constant CONDITIONAL_TOKEN_WEIGHT = 10.mul(BPool.BONE);
    uint256 public constant COLLATERAL_TOKEN_WEIGHT  = CONDITIONAL_TOKEN_WEIGHT.mul(2);

    constructor(address _factory) public {
        //TODO: what if to inherit the factory?
        BFactory factory = BFactory(_factory);

        address baseMarket = address(new Market());
        address baseBearToken = address(new ConditionalToken("Bear", "Bear"));
        address baseBullToken = address(new ConditionalToken("Bull", "Bull"));

        //Add moreoracles
        //Network: Kovan Aggregator: ETH/USD
        baseCurrencyToChainlinkFeed[
            uint256(1)
        ] = 0x9326BFA02ADD2366b30bacB125260Af641031331;
    }

    function create
    (
        address _collateralToken,
        uint256 _baseCurrencyID,
        uint256 _duration,
        uint256 _approvedBalance
    )
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
        //TODO: think what if _collateralDecimals is small
        //TODO: test if possible to set BPool.BONE as 10**_collateralDecimals
        //TODO: maybe should use the safeMath
        uint256 _initialBalance = _approvedBalance.div(2);

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
        addConditionalToken(_pool, _bearToken, _initialBalance);
        addConditionalToken(_pool, _bullToken, _initialBalance);
        addCollateralToken(_pool, IERC20(_collateralToken), _initialBalance);

        //TODO: send _initialBalance to the pool as the freezed money
        //_collateralToken.transferFrom(msg.sender, address(_pool), _initialBalance);

        //Set the swap fee
        _pool.setSwapFee(_swapFee);

        //Release the pool and allow public swaps
        _pool.release();

        //Get chainlink price feed by _baseCurrencyID
        address _chainlinkPriceFeed =
            baseCurrencyToChainlinkFeed[_baseCurrencyID];

        int256 _initialPrice =
            getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        require(_initialPrice > 0, "Chainlink error");

        //Make the market instead
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
                pool: address(_pool)
            });

        markets[currentMarketID] = marketStruct;

        emit Created(currentMarketID, now);

        //Increment current market ID
        currentMarketID++;
        //TODO: return address of the created market
    }

    function cloneBearToken(uint8 _decimals) internal returns (ConditionalToken) {
        address _bearToken = Clones.clone(baseBearToken);
        emit NewBearToken(_bearToken, now);
        ConditionalToken(_bearToken).cloneConstructor(_decimals)
        return ConditionalToken(_bearToken);
    }

    function cloneBullToken(uint8 _decimals) internal returns (ConditionalToken) {
        address _bullToken = Clones.clone(baseBullToken);
        emit NewBullToken(_bullToken, now);
        ConditionalToken(_bullToken).cloneConstructor(_decimals)
        return ConditionalToken(_bullToken);
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

    function calcSwapFee(uint8 _decimals) public returns (uint8) {
        //TODO: correct the calculation
        return (10 ** _decimals).div(1000).mul(3); // 0.3%
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
