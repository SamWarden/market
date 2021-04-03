pragma solidity ^0.6.0;

contract Migrations2 {
    address public owner;
    uint public lastCompletedMigration;

    constructor() public {
        owner = msg.sender;
    }

    modifier restricted() {
        if (msg.sender == owner) _;
    }

    function setCompleted(uint completed) external restricted {
        lastCompletedMigration = completed;
    }

    function upgrade(address new_address) external restricted {
        Migrations2 upgraded = Migrations2(new_address);
        upgraded.setCompleted(lastCompletedMigration);
    }
}
