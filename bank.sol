// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./safeERC20.sol";


contract TokenBank {
    using SafeERC20 for IERC20;
    
    uint8 nativeDecimal;
    address admin;
    address minter;

    // 添加地址到名称的映射
    mapping(string => address) tokenNames; 
    mapping(string => uint8) tokenDecimals; 

    //mapping(uint256=> address) nativeMappings;

    mapping(bytes32 => uint8) done; 

    // 事件：记录代币接收
    event TokenReceived(string token, address from, bytes target, uint256 amount, uint256 chainId, uint8 decimals);

    // 事件：记录代币提取
    event TokenWithdrawed(string token, address contractAddr, address target, uint256 amount);

    function init(uint8 _nativeDecimal) external{
        require(admin == address(0), "already inited");
        admin = msg.sender;
        nativeDecimal = _nativeDecimal;
    }

     // 查询合约中特定代币余额
    function getTokenBalance(string memory name) external view returns (uint256) {
        address _token = tokenNames[name];
        require(_token != address(0), "Invalid token name");

        return IERC20(_token).balanceOf(address(this));
    }
    
    // 接收代币的函数
    function depositToken(string memory name, uint256 _amount, bytes memory target) payable external {
        if (msg.value>0){
            emit TokenReceived("native", msg.sender, target, msg.value, block.chainid, nativeDecimal);
            return ;
        }

        require(_amount > 0, "Amount must be greater than 0");

        address _token = tokenNames[name];
        require(_token != address(0), "Invalid token name");
        
        IERC20 token = IERC20(_token);
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        uint8 decimal = tokenDecimals[name];
        emit TokenReceived(name, msg.sender, target, _amount, block.chainid,decimal);
    }

     // 提币函数
    function withdrawToken(string memory name, address payable target, uint256 _amount, uint256 chainId, uint8 decimals, bytes memory signature) external { 
        require(_amount > 0, "Amount must be greater than 0");
        require(signature.length != 65,'signature must = 65');
        require(chainId==block.chainid,'chainId error');

        bytes memory str = abi.encodePacked(name,target,_amount,chainId,decimals);
        bytes32 hashmsg = keccak256(str);
        require(done[hashmsg]==0,"already done");

        address tmp = recover(hashmsg,signature);
        require(tmp==minter, "invalid minter");
    
        if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("native"))) {
            require(target.send(_amount),"Transfer failed");
            emit TokenWithdrawed("native", address(0), target, _amount);
        }else{
            address _token = tokenNames[name];
            require(_token != address(0), "Invalid token address");

            IERC20 token = IERC20(_token);
            require(token.transfer(target, _amount), "Transfer failed");
            emit TokenWithdrawed(name,_token, target, _amount);
        }  

        
        done[hashmsg] = 1; // 防止重放
    }
   
    // demo, never used
    // function mintToken(string memory name, address target, uint256 _amount, uint256 chainId, uint8 decimals, bytes memory signature) external { 
    //     require(_amount > 0, "Amount must be greater than 0");
    //     require(signature.length != 65,'signature must = 65');

    //     bytes memory str = abi.encodePacked(name,target,_amount,chainId,decimals);
    //     bytes32 hashmsg = keccak256(str);
    //     require(done[hashmsg]==0,"already done");
    //     done[hashmsg] = 1; // 防止重放

    //     address tmp = recover(hashmsg,signature);
    //     require(tmp==minter, "invalid minter");
    
    //     //todo: 处理decimal
    //     if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("native"))) {
    //         address _token = nativeMappings[chainId];
    //         require(_token != address(0), "Invalid token address");

    //         IERC20 token = IERC20(_token);
    //         require(token.transfer(target, _amount), "Transfer failed");
    //     }else{
    //         address _token = tokenNames[name];
    //         require(_token != address(0), "Invalid token address");

    //         IERC20 token = IERC20(_token);
    //         require(token.transfer(target, _amount), "Transfer failed");
    //     }  
    // }

    function recover(bytes32 hashmsg,bytes memory signedString) private pure returns (address)
    {
        bytes32  r = bytesToBytes32(slice(signedString, 0, 32));
        bytes32  s = bytesToBytes32(slice(signedString, 32, 32));
        bytes1   v = slice(signedString, 64, 1)[0];
        return ecrecoverDecode(hashmsg,r, s, v);
    }

    function slice(bytes memory data, uint start, uint len) private pure returns(bytes memory)
    {
        bytes memory b = new bytes(len);
        for(uint i = 0; i < len; i++){
            b[i] = data[i + start];
        }

        return b;
    }

    //使用ecrecover恢复地址
    function ecrecoverDecode(bytes32 hashmsg,bytes32 r, bytes32 s, bytes1  v1) private pure returns (address addr){
        uint8 v = uint8(v1);
        if(uint8(v) == 0 || uint8(v) == 1)
        {
            v = uint8(v1) + 27;
        }
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        addr = ecrecover(hashmsg, v, r, s);
    }

    //bytes转换为bytes32
    function bytesToBytes32(bytes memory source) private pure returns (bytes32 result) {
        assembly {
            result := mload(add(source, 32))
        }
    }




    function addToken(address token,  string memory name) external{
        require(msg.sender==admin,"invalid sender");
        require(tokenNames[name] == address(0), "duplicated name");

        // 获取 token 的 decimals
        uint8 decimals = IERC20Metadata(token).decimals();
        
        tokenNames[name] = token;
        tokenDecimals[name] = decimals;
    }

    function removeToken(string memory name) external{
        require(msg.sender==admin,"invalid sender");
        
    
        delete tokenNames[name];
        delete tokenDecimals[name];
    }

    // function addNativeToken(address token,  uint256 chainId) external{
    //     require(msg.sender==admin,"invalid sender");
    //     require(nativeMappings[chainId] == address(0), "duplicated name");


    //    nativeMappings[chainId] = token;
    // }

    // function removeNativeToken(uint256 chainId) external{
    //     require(msg.sender==admin,"invalid sender");
        
    //     delete nativeMappings[chainId];
    // }

    function changeAdmin(address newAdmin) external{
        require(msg.sender==admin,"invalid sender for changing");
        admin = newAdmin;
    }

    function setMinter(address _minter) external{
        require(msg.sender==admin,"invalid sender for changing");
        minter = _minter;
    }
}
