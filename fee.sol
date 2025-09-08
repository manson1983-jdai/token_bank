// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./safeERC20.sol";

contract FeeCalculator {
    address public admin;
    address public usdc;

    mapping(string => uint256) public baseFees; 
    mapping(string => uint256) public protocolFees; 
    mapping(string => uint8) public decimals; 
    mapping(string => address) public tokens;

    function init(address _usdc) external{
        require(admin == address(0), "already inited");
        admin = msg.sender;
        usdc = _usdc;
    }

    function changeOwner(address newOwner)external{
        require(admin == msg.sender,"no auth");
        admin = newOwner;
    }

    function addToken(string memory name, uint256 _baseFee,uint256 _protocolFee,uint8 _decimal, address _token)external{
        require(0 ==baseFees[name],"duplicated");

        baseFees[name] = _baseFee;
        protocolFees[name] = _protocolFee;
        decimals[name] = _decimal;
        tokens[name] = _token;
    }

    function chargeFee(string memory name, uint256 amount)external{
        require(0 !=baseFees[name],"no such token");
        uint256 baseFee = baseFees[name];
        require(IERC20(usdc).transferFrom(msg.sender, address(this), baseFee),"fee failed");


        uint256 protocolFee = protocolFees[name];
        if (0==protocolFee){
            return;
        }
        uint8 decimal = decimals[name];
        require(IERC20(tokens[name]).transferFrom(msg.sender, address(this), amount*protocolFee/10**decimal),"fee failed");
       
        return;
    }
}
