// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@chainlink/contracts/src/v0.6/interfaces/LinkTokenInterface.sol";
import "./ERC20.sol";
import "./ConditionalToken.sol";
import "./Market.sol";
import "./ChainlinkData.sol";

contract MarketFactory is Ownable, ChainlinkData {
    event Created(
        address indexed market,
        string  indexed feedCurrencyPair,
        string  indexed collateralCurrency,
        uint256         time,
        uint256         duration
    );

    event SetCollateralCurrency(
        string  indexed currencyName,
        address indexed collateralToken,
        uint256         time
    );

    event NewConditionalToken(
        address indexed contractAddress,
        string  indexed name,
        uint256         time
    );

    mapping(address => bool) internal markets;
    mapping(string => address) public collateralCurrencies;

    //Variables
    address[] public marketList;
    string[] public collateralCurrenciesList;

    //TODO: maybe the variables should be public
    address private baseMarket;
    address private baseConditionalToken;
    LinkTokenInterface private linkToken;

    uint public protocolFee;
    uint public swapFee;

    //Constants
    uint256 public constant CONDITIONAL_TOKEN_WEIGHT = 10 * 10**18;
    uint256 public constant COLLATERAL_TOKEN_WEIGHT  = CONDITIONAL_TOKEN_WEIGHT * 2;

    constructor(address _baseMarket, address _baseConditionalToken) public {
        baseMarket = _baseMarket;
        baseConditionalToken = _baseConditionalToken;
        linkToken = LinkTokenInterface(chainlinkTokenAddress());

        swapFee = 3000000000000000; //0.3%
    }

    function create(
        string memory _baseCurrency,
        string memory _collateralCurrency,
        uint256 _duration,
        uint256 _approvedBalance
    )
        public
        returns (address)
    {
        require(
            baseCurrencies[_baseCurrency],
            "MarketFactory: invalid base currency"
        );
        require(
            collateralCurrencies[_collateralCurrency] != address(0),
            "MarketFactory: invalid collateral currency"
        );
        require(
            _duration >= 600 seconds && _duration < 365 days,
            "MarketFactory: invalid duration"
        );

        ERC20 _collateralToken = ERC20(collateralCurrencies[_collateralCurrency]);
        uint8 _collateralDecimals = _collateralToken.decimals();

        //Pull collateral tokens from sender
        _collateralToken.transferFrom(msg.sender, address(this), _approvedBalance);

        //Pull link tokens for making requests
        linkToken.transferFrom(msg.sender, address(this), linkFee * 2);

        //Estamate initial balance tokens
        uint256 _initialBalance = SafeMath.div(_approvedBalance, 2);

        //Clone bull and bear ERC20 tokens
        ConditionalToken _bullToken = cloneConditionalToken("Bull", "Bull", _collateralDecimals);
        ConditionalToken _bearToken = cloneConditionalToken("Bear", "Bear", _collateralDecimals);

        //Clone the market with the balancer pool
        Market _market = cloneMarket(
            _collateralToken,
            _bullToken,
            _bearToken,
            _duration,
            _baseCurrency,
            _collateralCurrency
        );
        address _marketAddress = address(_market);

        //Allow the market mint and burn conditional tokens
        _bullToken.transferOwnership(_marketAddress);
        _bearToken.transferOwnership(_marketAddress);

        //Approve pool to buy tokens
        _collateralToken.approve(_marketAddress, _initialBalance);

        //Mint the conditional tokens
        _market.buy(_initialBalance);

        //Add conditional and collateral tokens to the pool with liqudity
        addToken(_marketAddress, _bullToken, _initialBalance, CONDITIONAL_TOKEN_WEIGHT);
        addToken(_marketAddress, _bearToken, _initialBalance, CONDITIONAL_TOKEN_WEIGHT);
        addToken(_marketAddress, _collateralToken, _initialBalance, COLLATERAL_TOKEN_WEIGHT);

        //Get initial LP tokens
        _market.finalize();

        //Make a request of price for this market
        requestPrice(_marketAddress, _market.open.selector, _baseCurrency);

        //Send LP tokens to the sender
        _market.transfer(msg.sender, _market.INIT_POOL_SUPPLY());
        // _bullToken.transfer(msg.sender, _initialBalance);
        // _bearToken.transfer(msg.sender, _initialBalance);

        //Save the address of the market
        markets[_marketAddress] = true;
        marketList.push(_marketAddress);

        emit Created(_marketAddress, _baseCurrency, _collateralCurrency, now, _duration);
        return _marketAddress;
    }

    function isMarket(address _market) public view returns (bool) {
        return markets[_market];
    }

    function marketListLength() public view returns (uint256) {
        return marketList.length;
    }

    function collateralCurrenciesListLength() public view returns (uint256) {
        return collateralCurrenciesList.length;
    }

    function requestFinalPrice() external {
        //Make a request of price if sender is a market to its _close method
        require(markets[msg.sender], "MarketFactory: caller is not a market");
        requestPrice(msg.sender, Market(msg.sender)._close.selector, Market(msg.sender).baseCurrency());
    }

    function setProtocolFee(uint _protocolFee)
        external
        onlyOwner
    {
        // //TODO: is there need these requrements?
        // require(_protocolFee >= MIN_FEE, "ERR_MIN_FEE");
        // require(_protocolFee <= MAX_FEE, "ERR_MAX_FEE");
        protocolFee = _protocolFee;
    }

    function setSwapFee(uint _swapFee)
        external
        onlyOwner
    {
        // //TODO: is there need these requrements?
        require(_swapFee >= Market(baseMarket).MIN_FEE(), "ERR_MIN_FEE");
        require(_swapFee <= Market(baseMarket).MAX_FEE(), "ERR_MAX_FEE");
        swapFee = _swapFee;
    }

    function collect(address _token) external onlyOwner {
        //Send all tokens to the owner
        require(IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this))), "MarketFactory: collect transfer failed");
    }

    function setCollateralCurrency(
        string memory _currencyName,
        address _currencyToken
    ) public onlyOwner {
        if (_currencyToken != address(0)) {
            // If it's going to add a new currency
            // Save the _currencyName to collateralCurrenciesList if it isn't there
            if (collateralCurrencies[_currencyName] == address(0)) {
                collateralCurrenciesList.push(_currencyName);
            }
            // Add the address with the pair
        } else {
            // If it's going to delete the currency
            // Check that the currency is exists
            require(collateralCurrencies[_currencyName] != address(0), "MarketFactory: there isn't this currency in the list of collateralCurrencies");
            // Find and remove the curency
            for (uint8 i = 0; i < collateralCurrenciesList.length; i++) {
                if (keccak256(abi.encodePacked(collateralCurrenciesList[i])) == keccak256(abi.encodePacked(_currencyName))) {
                    // Shift the last element to index of the deleted pair
                    collateralCurrenciesList[i] = collateralCurrenciesList[collateralCurrenciesList.length - 1];
                    collateralCurrenciesList.pop();
                    break;
                }
            }
        }
        collateralCurrencies[_currencyName] = _currencyToken;
        SetCollateralCurrency(_currencyName, _currencyToken, now);
    }

    function cloneMarket(
        ERC20 _collateralToken,
        ConditionalToken _bullToken,
        ConditionalToken _bearToken,
        uint256 _duration,
        string memory _baseCurrency,
        string memory _collateralCurrency
    )
        internal
        returns (Market)
    {
        Market _market = Market(Clones.clone(baseMarket));
        // emit NewMarket(address(_market), _baseCurrency, _collateralCurrency, now, _duration);
        _market.cloneConstructor(
            _collateralToken,
            _bullToken,
            _bearToken,
            _duration,
            _baseCurrency,
            _collateralCurrency,
            protocolFee
        );

        //Set the swap fee
        _market.setSwapFee(swapFee); //0.3%

        return _market;
    }

    function cloneConditionalToken(string memory _name, string memory _symbol, uint8 _decimals) internal returns (ConditionalToken) {
        ConditionalToken _conditionalToken = ConditionalToken(Clones.clone(baseConditionalToken));
        emit NewConditionalToken(address(_conditionalToken), _name, now);
        _conditionalToken.cloneConstructor(_name, _symbol, _decimals);
        return _conditionalToken;
    }

    function addToken(address _market, ERC20 _token, uint256 _balance, uint256 _denorm)
        internal
    {
        //Approve pool
        _token.approve(_market, _balance);

        //Add _token to the pool
        Market(_market).bind(address(_token), _balance, _denorm);
    }
}
