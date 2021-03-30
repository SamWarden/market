// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./balancer/BFactory.sol";
import "./ConditionalToken.sol";
import "./Chainlink.sol";

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

    //TODO: add list of markets
    mapping(address => bool) public markets;
    mapping(string => address) public colleteralCurrencies;

    //Variables
    BFactory private factory;

    address private baseMarket;
    address private baseBearToken;
    address private baseBullToken;

    //Constants
    uint256 public constant CONDITIONAL_TOKEN_WEIGHT = (10).mul(BPool.BONE);
    uint256 public constant COLLATERAL_TOKEN_WEIGHT  = CONDITIONAL_TOKEN_WEIGHT.mul(2);

    constructor(address _factory) public {
        address baseMarket = address(new Market());
        //Merge two tokens to baseConditionalToken
        address baseBearToken = address(new ConditionalToken("Bear", "Bear"));
        address baseBullToken = address(new ConditionalToken("Bull", "Bull"));

        //TODO: Add moreoracles
        //Network: Kovan Aggregator: ETH/USD
        feeds[
            "ETH/USD"
        ] = 0x9326BFA02ADD2366b30bacB125260Af641031331;

        colleteralCurrencies["DAI"] = 0x0;

        //TODO: what if to inherit the factory?
        // BFactory factory = BFactory(_factory);
    }

    function create(
        address _collateralCurrency,
        address _feedCurrencyPair,
        uint256 _duration,
        uint256 _approvedBalance
    )
        public retruns (address)
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
        IERC20 _collateralToken = IERC20(colleteralCurrencies[_collateralCurrency]);
        uint8 _collateralDecimals = _collateralToken.decimals();

        //Estamate balance tokens
        //TODO: think what if _collateralDecimals is small
        //TODO: test if possible to set BPool.BONE as 10**_collateralDecimals
        uint256 _initialBalance = _approvedBalance.div(2);

        //Calculate swap fee
        //TODO: correct the calculation
        uint256 _swapFee = calcSwapFee(_collateralDecimals);

        //Create a pool of the balancer
        //TODO: use the market instead of the pool
        address _marketAddress = cloneMarket(_bearToken, _bullToken);
        Market _market = Market(_marketAddress)

        //Contract factory (clone) for two ERC20 tokens
        ConditionalToken _bearToken = cloneBearToken(_collateralDecimals);
        ConditionalToken _bullToken = cloneBullToken(_collateralDecimals);


        //Add conditional and collateral tokens to the pool
        addConditionalToken(_market, _bearToken, _initialBalance);
        addConditionalToken(_market, _bullToken, _initialBalance);
        addCollateralToken(_market, _collateralToken, _initialBalance);

        //mint the LP token and send it to msg.sender
        // _market.joinswapExternAmountIn(address(_collateralToken), _initialBalance, 0);
        // _market.transfer(msg.sender, _initialBalance);

        //TODO: send _initialBalance to the pool as the freezed money
        //_collateralToken.transferFrom(msg.sender, address(_pool), _initialBalance);

        //Set the swap fee
        _market.setSwapFee(_swapFee);

        //Release the pool and allow public swaps
        _market.release();

        //Get chainlink price feed by _feedCurrencyPair
        address _chainlinkPriceFeed =
            feeds[_feedCurrencyPair];

        int256 _initialPrice =
            getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        require(_initialPrice > 0, "Chainlink error");

        marktes[_marketAddress] = true;
        emit Created(_marketAddress, now);

        return _marketAddress;
    }

    function calcSwapFee(uint8 _decimals) public view returns (uint8) {
        //TODO: make SafeMath.pow here
        return (10 ** _decimals).div(1000).mul(3); // 0.3%
    }

    function isMarket(address _market) public view returns (bool) {
        return markets[_market];
    }

    function cloneMarket(uint8 _decimals) internal returns (address) {
        //TODO: get the collateralCurrency and to get _chainlinkPriceFeed
        //Get chainlink price feed by _collateralCurrency
        // address _chainlinkPriceFeed =
        //     baseCurrencyToChainlinkFeed[collateralCurrency];
        address _market = Clones.clone(baseMarket);
        emit NewMarket(_market, now);
        Market(_market).cloneConstructor(_decimals)
        return _market;
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

    function addConditionalToken(Market _market, ConditionalToken _conditionalToken, uint256 _conditionalBalance)
        internal
    {
        //Mint bear and bull tokens
        _conditionalToken.mint(address(this), _conditionalBalance);

        //To allow the market to mint a conditional token
        _conditionalToken.transferOwnership(address(_market));

        addToken(_pool, _conditionalToken, _conditionalBalance, CONDITIONAL_TOKEN_WEIGHT);
    }

    function addCollateralToken(Market _market, IERC20 _collateralToken, uint256 _collateralBalance)
        internal
    {
        //Pull collateral tokens from sender
        //TODO: try to make the transfer to the pool directly
        _collateralToken.transferFrom(msg.sender, address(this), _collateralBalance);

        addToken(_pool, _collateralToken, _collateralBalance, COLLATERAL_TOKEN_WEIGHT);
    }

    function addToken(Market _market, IERC20 token, uint256 balance, uint256 denorm)
        internal
    {
        //Approve pool
        token.approve(address(_market), balance);

        //Add token to the pool
        _market.bind(address(token), balance, denorm);
    }
}
