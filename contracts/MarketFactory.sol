// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./ERC20.sol";
import "./ConditionalToken.sol";
import "./Market.sol";
import "./ChainlinkData.sol";
// import "./balancer/BConst.sol";

//TODO: what if to inherit the BFactory?
contract MarketFactory is Ownable, ChainlinkData {
    //TODO: add more info to events
    event Created(
        address indexed market,
        string  indexed feedCurrencyPair,
        string  indexed collateralCurrency,
        uint256         time,
        uint256         duration
    );

    event SetCurrency(
        string  indexed currencyName,
        address indexed _collateralToken,
        uint256         time
    );
    // event NewConditionalToken(address indexed contractAddress, uint256 _time);

    struct MarketStruct {
        bool exist;
        // uint marketID;
        uint totalDeposit;
        uint totalRedemption;
        address market;
    }

    //TODO: add list of markets and currencies
    mapping(address => MarketStruct) public markets;
    mapping(string => address) public colleteralCurrencies;

    //Variables
    address[] public marketList;
    string[] public colleteralCurrenciesList;

    //TODO: maybe the variables should be private
    address private baseMarket;
    address private baseConditionalToken;
    uint public protocolFee;
    uint public swapFee;
    address private factory;

    //Constants
    uint256 public constant CONDITIONAL_TOKEN_WEIGHT = 10 * 10**18;
    uint256 public constant COLLATERAL_TOKEN_WEIGHT  = CONDITIONAL_TOKEN_WEIGHT * 2;

    constructor(address _baseMarket, address _baseConditionalToken, address _collateralToken) public {
        baseMarket = _baseMarket;
        baseConditionalToken = _baseConditionalToken;

        colleteralCurrencies["DAI"] = _collateralToken; //0x9326BFA02ADD2366b30bacB125260Af641031331; //!WRONG ADDRESS

        swapFee = Market(_baseMarket).MIN_FEE();
        factory = msg.sender;
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
        // require(
        //     _duration >= 600 seconds && _duration < 365 days,
        //     "Invalid duration"
        // );

        //TODO: check if _collateralToken is a valid ERC20 contract
        ERC20 _collateralToken = ERC20(colleteralCurrencies[_collateralCurrency]);
        uint8 _collateralDecimals = _collateralToken.decimals();

        //Estamate balance tokens
        uint256 _initialBalance = SafeMath.div(_approvedBalance, 2);

        //Pull collateral tokens from sender
        _collateralToken.transferFrom(msg.sender, address(this), _initialBalance);

        //Contract factory (clone) for two ERC20 tokens
        ConditionalToken _bullToken = cloneConditionalToken("Bull", "Bull", _collateralDecimals);
        ConditionalToken _bearToken = cloneConditionalToken("Bear", "Bear", _collateralDecimals);

        //Create a pool of the balancer
        //TODO: use the market instead of the pool
        Market _market = cloneMarket(
            _collateralToken,
            _bullToken,
            _bearToken,
            _duration,
            _collateralCurrency,
            _feedCurrencyPair
        );
        address _marketAddress = address(_market);

        //Set the swap fee
        _market.setSwapFee(swapFee);

        //Add conditional and collateral tokens to the pool with liqudity
        addConditionalToken(_marketAddress, _bullToken, _initialBalance);
        addConditionalToken(_marketAddress, _bearToken, _initialBalance);
        addToken(_marketAddress, _collateralToken, _initialBalance, COLLATERAL_TOKEN_WEIGHT);
        // addCollateralToken(_marketAddress, _collateralToken, _initialBalance);

        //Finalize the pool, get initial LP tokens and allow public swaps
        _market.finalize();

        MarketStruct memory marketStruct =
            MarketStruct({
                exist: true,
                totalDeposit: 0,
                totalRedemption: 0,
                market: _marketAddress
            });

        //Save the market
        markets[_marketAddress] = marketStruct;
        marketList.push(_marketAddress);

        //Approve pool to buy tokens
        _collateralToken.approve(_marketAddress, _initialBalance);

        //Mint the conditional tokens
        buy(_marketAddress, _initialBalance);

        //Send LP and bought conditional tokens to the sender
        _market.transfer(msg.sender, _market.INIT_POOL_SUPPLY());
        // _bullToken.transfer(msg.sender, _initialBalance);
        // _bearToken.transfer(msg.sender, _initialBalance);

        // emit Created(_marketAddress, _feedCurrencyPair, _collateralCurrency, now, _duration);

        return _marketAddress;
    }

    function close(address _marketAddress)
        external
        // _logs_
        // _lock_
    {
        Market _market = Market(_marketAddress);
        require(markets[_marketAddress].exist, "Market doesn't exist");
        require(_market.stage() == Market.Stages.Open, "MarketFactory: this market is not open");
        // now > created + duration
        require(
            now > SafeMath.add(
                _market.created(),
                _market.duration()
            ),
            "Market closing time hasn't yet arrived"
        );
        //Get chainlink price feed by _baseCurrencyID
        // address _chainlinkPriceFeed =
        //     baseCurrencyToChainlinkFeed[markets[_market].baseCurrencyID];

        //TODO: Query chainlink
        int256 price = 1;
        int256 _finalPrice = price;

        //TODO: maybe should move it to the method?
        // require(finalPrice > 0, "Chainlink error");
        //TODO: require(initialPrice != _finalPrice, "Price didn't change");

        require(_finalPrice > 0, "Chainlink error");
        // require(markets[_market].initialPrice != _finalPrice, "Price didn't change");
        
        _market.close(_finalPrice);
        
        // emit Closed(_market, now, finalPrice, result, winningToken);
    }

    //Buy new token pair for collateral token
    function buy(address _marketAddress, uint _amount)
        public
        // _logs_
        // _lock_
    {
        Market _market = Market(_marketAddress);
        require(markets[_marketAddress].exist, "Market doesn't exist");
        require(_market.stage() == Market.Stages.Open, "MarketFactory: this market is not open");
        require(_amount > 0, "Invalid amount");

        //Deposit collateral
        require(ERC20(_market.collateralToken()).transferFrom(msg.sender, address(this), _amount));

        //Mint both tokens for user
        ConditionalToken(_market.bearToken()).mint(msg.sender, _amount);
        ConditionalToken(_market.bullToken()).mint(msg.sender, _amount);

        //Increase total deposited collateral
        markets[_marketAddress].totalDeposit = SafeMath.add(
            markets[_marketAddress].totalDeposit,
            _amount
        );

        //TODO: addd the _market arg
        // emit Buy(_market, msg.sender, _amount, now);
    }

    function redeem(address _marketAddress, uint _amount)
        external
        // _logs_
        // _lock_
    {
        Market _market = Market(_marketAddress);
        require(markets[_marketAddress].exist, "Market doesn't exist");
        require(_market.stage() == Market.Stages.Closed, "MarketFactory: this market is not closed");
        require(_amount > 0, "Invalid amount");
        require(markets[_marketAddress].totalDeposit >= SafeMath.add(markets[_marketAddress].totalRedemption, _amount), "No collateral left");

        if (_market.result() != Market.Results.Draw) {
            //If there is winner
            //Burn win tokens from a sender
            ConditionalToken(_market.winningToken()).burnFrom(msg.sender, _amount);
        } else {
            // if a Draw
            // address -= addressAllowance / ((bearAllow + bullAllow) / (amount * 2))
            // Get allowance of conditional tokens from the sender
            ConditionalToken _bullToken = ConditionalToken(_market.bullToken());
            ConditionalToken _bearToken = ConditionalToken(_market.bearToken());
            uint256 _bullAllowance = _bullToken.allowance(msg.sender, address(this));
            uint256 _bearAllowance = _bearToken.allowance(msg.sender, address(this));
            require(SafeMath.add(_bullAllowance, _bearAllowance) < SafeMath.mul(_amount, 2), "Total allowance of conditonal tokens is lower than the given amount");
            // ratio = totalAllowance / conditionalAmount
            uint256 ratio = SafeMath.div(SafeMath.add(_bullAllowance, _bearAllowance), SafeMath.mul(_amount, 2));

            // if not 0, burn the tokens
            if (_bullAllowance > 0) {
               _bullToken.burnFrom(msg.sender, SafeMath.div(_bullAllowance, ratio));
            }
            if (_bearAllowance > 0) {
                _bearToken.burnFrom(msg.sender, SafeMath.div(_bearAllowance, ratio));
            }
        }
        uint _protocolFee = SafeMath.mul(_amount, _market.protocolFee());

        ERC20(_market.collateralToken()).transfer(msg.sender, SafeMath.sub(_amount, _protocolFee));
        ERC20(_market.collateralToken()).transfer(factory, _protocolFee);

        //Increase total redemed collateral
        markets[_marketAddress].totalRedemption = SafeMath.add(markets[_marketAddress].totalRedemption, _amount);

        //TODO: use the event
        // emit Redeem(msg.sender, _amount, now);
    }

    function isMarket(address _market) public view returns (bool) {
        return markets[_market].exist;
    }

    function setProtocolFee(uint _protocolFee)
        external
        onlyOwner
    {
        // require(!_finalized, "ERR_IS_FINALIZED");
        // //TODO: is there need these requrements?
        // require(_protocolFee >= MIN_FEE, "ERR_MIN_FEE");
        // require(_protocolFee <= MAX_FEE, "ERR_MAX_FEE");
        protocolFee = _protocolFee;
    }

    function setSwapFee(uint _swapFee)
        external
        onlyOwner
    {
        // require(!_finalized, "ERR_IS_FINALIZED");
        // //TODO: is there need these requrements?
        require(_swapFee >= Market(baseMarket).MIN_FEE(), "ERR_MIN_FEE");
        require(_swapFee <= Market(baseMarket).MAX_FEE(), "ERR_MAX_FEE");
        swapFee = _swapFee;
    }

    function collect(address _token)
        external
        onlyOwner
    {
        //Send all tokens to the owner
        require(IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this))), "ERR_ERC20_FAILED");
    }

    function setCollateralCurrency(
        string memory _currencyName,
        address _currencyToken
    ) public onlyOwner {
        if (_currencyToken != address(0)) {
            // If it's going to add a new currency
            // Save the _currencyName to colleteralCurrenciesList if it isn't there
            if (colleteralCurrencies[_currencyName] == address(0)) {
                colleteralCurrenciesList.push(_currencyName);
            }
            // Add the address with the pair
            colleteralCurrencies[_currencyName] = _currencyToken;
        } else {
            // If it's going to delete the currency
            // Check that the currency is exists
            require(colleteralCurrencies[_currencyName] != address(0), "There isn't this currency in the list of colleteralCurrencies");
            // Find and remove the curency
            for (uint8 i = 0; i < colleteralCurrenciesList.length; i++) {
                if (keccak256(abi.encodePacked(colleteralCurrenciesList[i])) == keccak256(abi.encodePacked(_currencyName))) {
                    // Shift the last element to index of the deleted pair
                    colleteralCurrenciesList[i] = colleteralCurrenciesList[colleteralCurrenciesList.length - 1];
                    colleteralCurrenciesList.pop();
                    break;
                }
            }
            // Clear the address of the pair
            colleteralCurrencies[_currencyName] = address(0);
        }
        // emit SetCurrency(_currencyName, _currencyToken, now);
    }

    function cloneMarket(
        ERC20 _collateralToken,
        ConditionalToken _bullToken,
        ConditionalToken _bearToken,
        uint256 _duration,
        string memory _collateralCurrency,
        string memory _feedCurrencyPair
    )
        internal
        returns (Market)
    {
        //Get chainlink price feed by _feedCurrencyPair
        address _chainlinkPriceFeed = feeds[_feedCurrencyPair];

        Market _market = Market(Clones.clone(baseMarket));
        // emit NewMarket(address(_market), now);
        _market.cloneConstructor(
            address(_collateralToken),
            address(_bullToken),
            address(_bearToken),
            _duration,
            _collateralCurrency,
            _feedCurrencyPair,
            _chainlinkPriceFeed,
            protocolFee
        );
        return _market;
    }

    function cloneConditionalToken(string memory _name, string memory _symbol, uint8 _decimals) internal returns (ConditionalToken) {
        ConditionalToken _conditionalToken = ConditionalToken(Clones.clone(baseConditionalToken));
        // emit NewConditionalToken(address(_conditionalToken), now, _name, _symbol, _decimals);
        _conditionalToken.cloneConstructor(_name, _symbol, _decimals);
        return _conditionalToken;
    }

    function addConditionalToken(address _market, ConditionalToken _conditionalToken, uint256 _conditionalBalance)
        internal
    {
        //Mint bear and bull tokens
        _conditionalToken.mint(address(this), _conditionalBalance);

        addToken(_market, _conditionalToken, _conditionalBalance, CONDITIONAL_TOKEN_WEIGHT);
    }

    // function addCollateralToken(address _market, ERC20 _collateralToken, uint256 _collateralBalance)
    //     internal
    // {
    //     //Pull collateral tokens from sender
    //     //TODO: try to make the transfer to the pool directly
    //     _collateralToken.transferFrom(msg.sender, address(this), _collateralBalance);

    //     addToken(_market, _collateralToken, _collateralBalance, COLLATERAL_TOKEN_WEIGHT);
    // }

    function addToken(address _market, ERC20 _token, uint256 _balance, uint256 _denorm)
        internal
    {
        //Approve pool
        _token.approve(_market, _balance);

        //Add _token to the pool
        Market(_market).bind(address(_token), _balance, _denorm);
    }
}
