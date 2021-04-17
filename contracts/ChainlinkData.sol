// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ConditionalToken.sol";

contract ChainlinkData is Ownable, ChainlinkClient {
    struct RequestsStruct {
        address target;
        bytes4 func;
    }

    event SetBaseCurrency(
        string  indexed baseCurrency,
        bool    indexed value,
        uint256         time
    );

    mapping(bytes32 => RequestsStruct) private requests;
    mapping(string => bool) public baseCurrencies;

    string[] public baseCurrenciesList; //list of keys for `baseCurrencies`

    address private oracle;
    bytes32 private jobId;
    uint256 private fee;

    constructor() public {

        // oracle = 0x72f3dFf4CD17816604dd2df6C2741e739484CA62;
        // jobId = "bfc49c95584c4b10b61fc88bb2023d68";
        // XdFeed

        setPublicChainlinkToken();
        //Network: Kovan, job: GET -> int256
        oracle = 0x2f90A6D021db21e1B2A077c5a37B3C7E75D15b7e;
        jobId = "ad752d90098243f8a5c91059d3e5616c";
        fee = 0.1 * 10 ** 18; // 0.1 LINK
    }

    function requestPrice(address _target, bytes4 _func, string memory _symbol) internal {
        Chainlink.Request memory _request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);
        _request.add("get", string(abi.encodePacked(
            "https://pro-api.coinmarketcap.com/v1/tools/price-conversion?CMC_PRO_API_KEY=680cb675-8562-4f06-9336-3eeef35eb575&amount=1&convert=USD&symbol=", //&time=1618613496
            _symbol
        )));
        _request.add("path", "data.quote.USD.price");
        _request.addUint("times", 10**18);

        // https://min-api.cryptocompare.com/data/pricehistorical?fsym=ETH&tsyms=USD&ts=1618571480
        // _request.add("get", "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd");
        // _request.add("path", "bitcoin.usd");
        // request.add("path", "price");
        // request.add("base", "BTC/USDT:CXDXF");
        // request.addUint("until", now + _timeout);

        bytes32 _requestId = sendChainlinkRequestTo(oracle, _request, fee);
        RequestsStruct memory _req = RequestsStruct({
            target: _target,
            func: _func
        });
        requests[_requestId] = _req;
    }

    /**
     * Receive the response in the form of int256
     */ 
    function fulfill(bytes32 _requestId, int256 _price) external recordChainlinkFulfillment(_requestId)
    {
        bytes memory _data = abi.encodeWithSelector(requests[_requestId].func, _price);
        (bool _success, ) = address(requests[_requestId].target).call(_data);
        require(_success, "ChainlinkData: Request failed");
    }

    // function setBaseCurrencies(byte[5][] memory _newBaseCurrencies) external onlyOwner {
    //     //Remove (set `false`) all old base currencies in the baseCurrencies mapping
    //     for (uint8 i = 0; i < baseCurrenciesList.length; i++) {
    //         baseCurrencies[baseCurrenciesList[i]] = false;
    //     }
    //     //Add (set `true`) all new base currencies to the baseCurrencies mapping
    //     for (uint8 i = 0; i < _newBaseCurrencies.length; i++) {
    //         baseCurrencies[_newBaseCurrencies[i]] = true;
    //     }
    //     //Set this new base currencies list
    //     baseCurrenciesList = _newBaseCurrencies;
    // }

    function setBaseCurrency(string memory _baseCurrency, bool _value) external onlyOwner {
        if (_value) {
            // If it's going to add a new currency
            // Save the _baseCurrency to baseCurrenciesList if it isn't there
            if (!baseCurrencies[_baseCurrency]) {
                baseCurrenciesList.push(_baseCurrency);
            }
        } else {
            // If it's going to delete the currency
            // Check that the currency is exists
            require(baseCurrencies[_baseCurrency], "There isn't such base currency in the list of baseCurrencies");
            // Find and remove the currency
            for (uint8 i = 0; i < baseCurrenciesList.length; i++) {
                if (keccak256(abi.encodePacked(baseCurrenciesList[i])) == keccak256(abi.encodePacked(_baseCurrency))) {
                    // Shift the last element to index of the deleted currency
                    baseCurrenciesList[i] = baseCurrenciesList[baseCurrenciesList.length - 1];
                    baseCurrenciesList.pop();
                    break;
                }
            }
        }
        baseCurrencies[_baseCurrency] = _value;
        SetBaseCurrency(_baseCurrency, _value, now);
    }

    function setChainlink(address _oracle, bytes32 _jobId, uint256 _fee) external onlyOwner {
        oracle = _oracle;
        jobId = _jobId;
        fee = _fee;
    }

    /**
     * Returns the latest price
     */
    function getHistoricalPriceByTimestamp(AggregatorV3Interface _feed, uint256 _timestamp)
        external
        view
        returns (int256)
    {
        (
            uint80 _roundID,
            int256 _price,
            uint256 _startedAt,
            uint256 _roundTimeStamp,
            uint80 _answeredInRound
        ) = _feed.latestRoundData();
        //Search untill startedAt > _timestamp
        while (_roundTimeStamp == 0 || _startedAt > _timestamp) {
            _roundID--;
            (
                _roundID,
                _price,
                _startedAt,
                _roundTimeStamp,
                _answeredInRound
            ) = _feed.getRoundData(_roundID);
        }
        return _price;
    }
    function getLatestPrice(address _feed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return AggregatorV3Interface(_feed).latestRoundData();
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
    
    function getHistoricalPrice(address _feed, uint80 _roundId)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return AggregatorV3Interface(_feed).getRoundData(_roundId);
    }

    // function getHistoricalPrice(AggregatorV3Interface _feed, uint80 _roundId)
    //     public
    //     view
    //     returns (int256)
    // {
    //     (
    //         uint80 _roundID,
    //         int256 _price,
    //         uint256 _startedAt,
    //         uint256 _timeStamp,
    //         uint80 _answeredInRound
    //     ) = _feed.getRoundData(_roundId);
    //     require(_timeStamp > 0, "Round not complete");
    //     return _price;
    // }
}
