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

    mapping(string => address) public feeds;
    string[] public feedsPairs;

    function setFeed(
        string _keyPair,
        address _chainlinkFeed
    ) public onlyOwner {
        //Save the _keyPair to feedsPais if it isn't there and add the feed with the pair
        if (feeds[_keyPair] == address(0)) {
            feedsPairs.push(_keyPair)
        }
        feeds[_keyPair] = _chainlinkFeed; 
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

}
