// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./balancer/BFactory.sol";
import "./ConditionalToken.sol";

contract MarketFactory is Ownable {
    // using SafeMath for uint256, uint8;

    mapping(string => address) public feeds;

    AggregatorV3Interface internal priceFeed;
    string[] public feedPairs;

    function setFeed(
        string _currencyPair,
        address _chainlinkFeed
    ) public onlyOwner {
        //TODO: or allow set address(0) and delete the pair from feedPairs
        require(_chainlinkFeed != address(0), "Address of chainlink feed cannot be 0")
        //Save the _currencyPair to feedPairs if it isn't there and add the feed with the pair
        if (feeds[_currencyPair] == address(0)) {
            feedPairs.push(_currencyPair)
        }
        feeds[_currencyPair] = _chainlinkFeed; 
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
            roundId--;
            (
                _roundID,
                _price,
                _startedAt,
                _roundTimeStamp,
                _answeredInRound
            ) = _feed.getRoundData(_roundId);
        }
        return _price
    }
    function getLatestPrice(AggregatorV3Interface _feed)
        public
        view
        returns (int256)
    {
        (
            uint80 _roundID,
            int256 _price,
            uint256 _startedAt,
            uint256 _timeStamp,
            uint80 _answeredInRound
        ) = _feed.latestRoundData();
        return _price;
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
    function getHistoricalPrice(AggregatorV3Interface _feed, uint80 _roundId)
        public
        view
        returns (int256)
    {
        (
            uint80 _roundID,
            int256 _price,
            uint256 _startedAt,
            uint256 _timeStamp,
            uint80 _answeredInRound
        ) = _feed.getRoundData(_roundId);
        require(_timeStamp > 0, "Round not complete");
        return _price;
    }

}
