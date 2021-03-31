// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./ConditionalToken.sol";
import "./Market.sol";
import "./balancer/BConst.sol";

contract MarketFactory is Ownable {
    using SafeMath for uint256;
    using SafeMath for uint8;

    //TODO: add more info to events
    event Created(uint256 indexed marketID, uint256 _time);
    event Resumed(uint256 indexed marketID, uint256 _time);
    event Closed(uint256 indexed marketID, uint256 _time);
    event Buy(uint256 indexed marketID, uint256 _time);
    event Redeem(uint256 indexed marketID, uint256 _time);
    event NewBearToken(address indexed contractAddress, uint256 _time);
    event NewBullToken(address indexed contractAddress, uint256 _time);

    //TODO: add list of markets
    mapping(address => bool) public markets;
    mapping(string => address) public colleteralCurrencies;
    mapping(string => address) public feeds;

    string[] public feedPairs;

    //Variables
    // BFactory private factory;
    address private baseMarket;
    address private baseBearToken;
    address private baseBullToken;

    //Constants
    // uint256 public constant CONDITIONAL_TOKEN_WEIGHT = (10).mul(BConst.BONE);
    uint256 public constant CONDITIONAL_TOKEN_WEIGHT = 10 * 10**18;
    uint256 public constant COLLATERAL_TOKEN_WEIGHT  = CONDITIONAL_TOKEN_WEIGHT * 2;

    constructor(address _factory) public {
        baseMarket = address(new Market());
        //Merge two tokens to baseConditionalToken
        baseBearToken = address(new ConditionalToken("Bear", "Bear"));
        baseBullToken = address(new ConditionalToken("Bull", "Bull"));

        //TODO: Add moreoracles
        //Network: Kovan Aggregator: ETH/USD
        feeds[
            "ETH/USD"
        ] = 0x9326BFA02ADD2366b30bacB125260Af641031331;

        //!WRONG ADDRESS
        colleteralCurrencies["DAI"] = 0x9326BFA02ADD2366b30bacB125260Af641031331;

        //TODO: what if to inherit the factory?
        // BFactory factory = BFactory(_factory);
    }

    function create(
        string memory _collateralCurrency,
        string memory _feedCurrencyPair,
        uint256 _duration,
        uint256 _approvedBalance
    )
        public
        returns (address)
    {
        require(
            colleteralCurrencies[_collateralCurrency] != address(0),
            "Invalid colleteral currency"
        );
        require(
            feeds[_feedCurrencyPair] != address(0),
            "Invalid currency pair"
        );
        require(
            _duration >= 600 seconds && _duration < 365 days,
            "Invalid duration"
        );

        //TODO: check if _collateralToken is a valid ERC20 contract
        ERC20 _collateralToken = ERC20(colleteralCurrencies[_collateralCurrency]);
        uint8 _collateralDecimals = _collateralToken.decimals();

        //Estamate balance tokens
        uint256 _initialBalance = _approvedBalance.div(2);

        //Calculate swap fee
        //TODO: think what if _collateralDecimals is small
        //TODO: test if possible to set BPool.BONE as 10**_collateralDecimals
        //TODO: correct the calculation
        uint256 _swapFee = calcSwapFee(_collateralDecimals);

        //Contract factory (clone) for two ERC20 tokens
        ConditionalToken _bearToken = cloneBearToken(_collateralDecimals);
        ConditionalToken _bullToken = cloneBullToken(_collateralDecimals);

        //Create a pool of the balancer
        //TODO: use the market instead of the pool
        address _marketAddress = cloneMarket(
            _collateralToken,
            _bearToken,
            _bullToken,
            _duration,
            _collateralCurrency,
            _feedCurrencyPair
        );
        Market _market = Market(_marketAddress);

        //Set the swap fee
        _market.setSwapFee(_swapFee);

        //Add conditional and collateral tokens to the pool with liqudity
        addConditionalToken(_marketAddress, _bearToken, _initialBalance);
        addConditionalToken(_marketAddress, _bullToken, _initialBalance);
        addCollateralToken(_marketAddress, _collateralToken, _initialBalance);

        //Mint the conditional tokens
        _market.buy(_initialBalance);

        //Send bought conditional token to the sender
        _bullToken.transfer(msg.sender, _initialBalance);
        _bearToken.transfer(msg.sender, _initialBalance);

        //Finalize the pool and allow public swaps
        _market.finalize();

        markets[_marketAddress] = true;
        // emit Created(_marketAddress, now);

        return _marketAddress;
    }

    function calcSwapFee(uint8 _decimals) public view returns (uint8) {
        //TODO: make SafeMath.pow here
        return (10 ** _decimals).div(1000).mul(3); // 0.3%
    }

    function isMarket(address _market) public view returns (bool) {
        return markets[_market];
    }

    function cloneMarket(
        ERC20 _collateralToken,
        ConditionalToken _bearToken,
        ConditionalToken _bullToken,
        uint256 _duration,
        string memory _collateralCurrency,
        string memory _feedCurrencyPair
    )
        internal
        returns (address)
    {
        //Get chainlink price feed by _feedCurrencyPair
        address _chainlinkPriceFeed = feeds[_feedCurrencyPair];

        address _market = Clones.clone(baseMarket);
        // emit NewMarket(_market, now);
        Market(_market).cloneConstructor(
            _collateralToken,
            _bearToken,
            _bullToken,
            _duration,
            _collateralCurrency,
            _feedCurrencyPair,
            _chainlinkPriceFeed
        );
        return _market;
    }

    function setFeed(
        string memory _currencyPair,
        address _chainlinkFeed
    ) public onlyOwner {
        //TODO: or allow set address(0) and delete the pair from feedPairs
        require(_chainlinkFeed != address(0), "Address of chainlink feed cannot be 0");
        //Save the _currencyPair to feedPairs if it isn't there and add the feed with the pair
        if (feeds[_currencyPair] == address(0)) {
            feedPairs.push(_currencyPair);
        }
        feeds[_currencyPair] = _chainlinkFeed; 
    }

    function cloneBearToken(uint8 _decimals) internal returns (ConditionalToken) {
        address _bearToken = Clones.clone(baseBearToken);
        // emit NewBearToken(_bearToken, now);
        ConditionalToken(_bearToken).cloneConstructor(_decimals);
        return ConditionalToken(_bearToken);
    }

    function cloneBullToken(uint8 _decimals) internal returns (ConditionalToken) {
        address _bullToken = Clones.clone(baseBullToken);
        // emit NewBullToken(_bullToken, now);
        ConditionalToken(_bullToken).cloneConstructor(_decimals);
        return ConditionalToken(_bullToken);
    }

    function addConditionalToken(address _market, ConditionalToken _conditionalToken, uint256 _conditionalBalance)
        internal
    {
        //Mint bear and bull tokens
        _conditionalToken.mint(address(this), _conditionalBalance);

        //To allow the market to mint a conditional token
        _conditionalToken.transferOwnership(_market);

        addToken(_market, _conditionalToken, _conditionalBalance, CONDITIONAL_TOKEN_WEIGHT);
    }

    function addCollateralToken(address _market, ERC20 _collateralToken, uint256 _collateralBalance)
        internal
    {
        //Pull collateral tokens from sender
        //TODO: try to make the transfer to the pool directly
        _collateralToken.transferFrom(msg.sender, address(this), _collateralBalance);

        addToken(_market, _collateralToken, _collateralBalance, COLLATERAL_TOKEN_WEIGHT);
    }

    function addToken(address _market, ERC20 token, uint256 balance, uint256 denorm)
        internal
    {
        //Approve pool
        token.approve(_market, balance);

        //Add token to the pool
        Market(_market).bind(address(token), balance, denorm);
    }
}
