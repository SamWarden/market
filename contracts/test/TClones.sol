// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/proxy/Clones.sol";

contract TClones {
    event Cloned(address indexed clone);

    function copy(address _contract) external returns (address) {
        address _clone = Clones.clone(_contract);
        emit Cloned(_clone);
        return _clone;
    }
}
