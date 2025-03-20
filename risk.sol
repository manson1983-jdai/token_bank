// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract RiskManager {

    address admin;

    function init() external{
        require(admin == address(0), "already inited");
        admin = msg.sender;
    }

    function approve(uint256 amount, string memory name, address target)external returns (bool){
        return amount<=10000*10**18;
    }
}
