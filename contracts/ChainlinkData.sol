// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ConditionalToken.sol";

contract ChainlinkData is Ownable, ChainlinkClient {
    int256[] log;
    // using SafeMath for uint256, uint8;
    struct RequestsStruct {
        address target;
        bytes4 func;
    }

    event SetFeed(string indexed currencyPair, address indexed chainlinkFeed, uint256 time);

    mapping(string => address) public feeds;
    mapping(bytes32 => RequestsStruct) public requests;
    string[] public feedPairs; //list of keys for `feeds`

    AggregatorV3Interface internal priceFeed;

    address private oracle;
    bytes32 private jobId;
    uint256 private fee;
    int256 public price;
    uint8 public called;

    constructor() public {
        //TODO: Add moreoracles
        //Network: Kovan Aggregator: ETH/USD
        feeds[
            "ETH/USD"
        ] = 0x9326BFA02ADD2366b30bacB125260Af641031331;

        // oracle = 0x72f3dFf4CD17816604dd2df6C2741e739484CA62;
        // jobId = "bfc49c95584c4b10b61fc88bb2023d68";
        // XdFeed

        setPublicChainlinkToken();
        oracle = 0x56dd6586DB0D08c6Ce7B2f2805af28616E082455;
        jobId = "0391a670ba8e4a2f80750acfe65b0c89";
        fee = 0.1 * 10 ** 18; // 0.1 LINK
    }

    function requestPrice(address _target, bytes4 _func) internal {

        Chainlink.Request memory _request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);
        _request.add("get", "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd");
        _request.add("path", "bitcoin.usd");
        // request.addUint("times", 10**18);
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

    function callMethod() public {
        int256 _price = 1;
        bytes memory _data = abi.encodeWithSelector(this.method.selector, _price);
        (bool _success, ) = address(this).staticcall(_data);
        require(_success, "ChainlinkData: Request failed");
    }
    function method(int256 _price) public {
        log.push(1);
        log.push(_price);
    }
    function makeReq() public {
        Chainlink.Request memory _request = buildChainlinkRequest(jobId, address(this), this.fulfill2.selector);
        _request.add("get", "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd");
        _request.add("path", "bitcoin.usd");
        bytes32 _requestId = sendChainlinkRequestTo(oracle, _request, fee);
    }
    function fulfill2(bytes32 _requestId, int256 _price) public recordChainlinkFulfillment(_requestId)
    {
        log.push(33);
        log.push(_price);
    }
    /**
     * Receive the response in the form of int256
     */ 
    function fulfill(bytes32 _requestId, int256 _price) public recordChainlinkFulfillment(_requestId)
    {
        log.push(22);
        bytes memory _data = abi.encodeWithSelector(requests[_requestId].func, _price);
        (bool _success, ) = address(requests[_requestId].target).staticcall(_data);
        require(_success, "ChainlinkData: Request failed");
    }

    function setFeed(
        string memory _currencyPair,
        address _chainlinkFeed
    ) public onlyOwner {
        if (_chainlinkFeed != address(0)) {
            // If it's going to add a new pair
            // Save the _currencyPair to feedPairs if it isn't there
            if (feeds[_currencyPair] == address(0)) {
                feedPairs.push(_currencyPair);
            }
            // Add the address with the pair
            feeds[_currencyPair] = _chainlinkFeed;
        } else {
            // If it's going to delete the pair
            // Check that the pair is exists
            require(feeds[_currencyPair] != address(0), "There isn't the currency pair in the list of feeds");
            // Find and remove the pair
            for (uint8 i = 0; i < feedPairs.length; i++) {
                if (keccak256(abi.encodePacked(feedPairs[i])) == keccak256(abi.encodePacked(_currencyPair))) {
                    // Shift the last element to index of the deleted pair
                    feedPairs[i] = feedPairs[feedPairs.length - 1];
                    feedPairs.pop();
                    break;
                }
            }
            // Clear the address of the pair
            feeds[_currencyPair] = address(0);
        }
        emit SetFeed(_currencyPair, _chainlinkFeed, now);
    }

    function setChainlink(address _oracle, bytes32 _jobId, uint256 _fee) public onlyOwner {
        oracle = _oracle;
        jobId = _jobId;
        fee = _fee;
    }

    /**
     * Returns the latest price
     */
    function getHistoricalPriceByTimestamp(AggregatorV3Interface _feed, uint256 _timestamp)
        public
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
