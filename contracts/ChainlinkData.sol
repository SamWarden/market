// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

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
    uint256 internal linkFee;

    constructor() public {
        setPublicChainlinkToken();
        //Network: Kovan, job: GET -> int256
        oracle = 0x2f90A6D021db21e1B2A077c5a37B3C7E75D15b7e;
        jobId = "ad752d90098243f8a5c91059d3e5616c";
        linkFee = 0.1 * 10 ** 18; // 0.1 LINK
    }

    function baseCurrenciesListLength() public view returns (uint256) {
        return baseCurrenciesList.length;
    }

    function requestPrice(address _target, bytes4 _func, string memory _symbol) internal {
        //TODO: add time=$TIMESTAMP to end of url
        Chainlink.Request memory _request = buildChainlinkRequest(jobId, address(this), this.fulfillRequest.selector);
        _request.add("get", string(abi.encodePacked(
            "https://pro-api.coinmarketcap.com/v1/tools/price-conversion?CMC_PRO_API_KEY=680cb675-8562-4f06-9336-3eeef35eb575&amount=1&convert=USD&symbol=",
            _symbol
        )));
        _request.add("path", "data.quote.USD.price");
        _request.addUint("times", 10**18);

        bytes32 _requestId = sendChainlinkRequestTo(oracle, _request, linkFee);
        RequestsStruct memory _req = RequestsStruct({
            target: _target,
            func: _func
        });
        requests[_requestId] = _req;
    }

    /**
     * Receive the response in the form of int256
     */ 
    function fulfillRequest(bytes32 _requestId, int256 _price) external recordChainlinkFulfillment(_requestId)
    {
        bytes memory _data = abi.encodeWithSelector(requests[_requestId].func, _price);
        (bool _success, ) = address(requests[_requestId].target).call(_data);
        require(_success, "ChainlinkData: Request failed");
    }

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

    function setChainlink(address _oracle, bytes32 _jobId, uint256 _linkFee) external onlyOwner {
        oracle = _oracle;
        jobId = _jobId;
        linkFee = _linkFee;
    }
}
