// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./safeERC20.sol";
import "./risk.sol";

contract TokenBank {
    using SafeERC20 for IERC20;

    string natinveName;
   
    address public admin;
    address minter;
    address approver;

    RiskManager private risk;

    // 添加地址到名称的映射
    mapping(string => address) public tokenNames; 
    mapping(string => uint8) public tokenDecimals; 

    mapping(uint256=>uint64) public nonces;

    mapping(address => mapping(string =>uint256)) public liq;

    //mapping(uint256=> address) nativeMappings;

    mapping(bytes32 => uint8) done; 
    mapping(bytes32=>Application) waitingList;


    // 事件：记录代币接收
    event TokenReceived(uint64 nonce, string token, string target, uint256 amount, uint256 chainId, uint256 toChainId, uint8 decimals);

    // 事件：记录代币提取
    event TokenWithdrawed(string token, address contractAddr, address target, uint256 amount);

    // 事件：触发风控，人工审核
    event WaitingApp(bytes32 id, string name, address _token, address target, uint256 amount);

    event TokenWithdrawApproved(string token, address contractAddr, address target, uint256 amount);


    function setNonce(uint256 chainId, uint64 newNonce) external{
        require(msg.sender== admin,"no auth");
        nonces[chainId] = newNonce;
    }

    function init(string memory name) external{
        require(admin == address(0), "already inited");
        admin = msg.sender;
        natinveName = name;

       // risk = RiskManager(riskAddr);
    }

     // 查询合约中特定代币余额
    function getTokenBalance(string memory name) external view returns (uint256) {
        address _token = tokenNames[name];
        require(_token != address(0), "Invalid token name");

        return IERC20(_token).balanceOf(address(this));
    }
    
    // 接收代币的函数
    function depositToken(string memory name, uint256 _amount, uint256 toChainId, string memory target) payable external {
        if (msg.value>0){
            uint256 amount = convertBetweenDecimals(msg.value,18,9);
            emit TokenReceived(nonces[0], natinveName, target, amount, block.chainid, toChainId,9);
            nonces[0]+=1;
            return ;
        }

        require(_amount > 0, "Amount must be greater than 0");

        address _token = tokenNames[name];
        require(_token != address(0), "Invalid token name");
        
        IERC20 token = IERC20(_token);
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        uint8 decimal = tokenDecimals[name];
        uint8 targetDecimal = 9;
        if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("mix"))||keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("usdt"))||(keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("usdc")))){
            targetDecimal = 6;
        }
        uint256 amount = convertBetweenDecimals(_amount,decimal,targetDecimal);

        emit TokenReceived(nonces[toChainId], name, target, amount, block.chainid, toChainId, targetDecimal);
        nonces[toChainId]+=1;
    }

    // function testhash(bytes memory magic, uint64 nonce, string memory name, address payable target, uint64 _amount, uint64 fromChainId, uint64 tochain) public view returns (bytes32){
    //      bytes memory str = abi.encodePacked(magic, nonce, name,target,_amount,fromChainId, tochain);
    //     bytes32 hashmsg = keccak256(str);

    //     return hashmsg;
    // }

    // function testhashraw(bytes memory magic, uint64 nonce, string memory name, address payable target, uint64 _amount, uint64 fromChainId, uint64 tochain ) public view returns (bytes memory){
    //     bytes memory str = abi.encodePacked(magic, nonce, name,target,_amount,fromChainId, tochain);
    //     return str;
    // }

     // 提币函数
    function withdrawToken(bytes memory magic, uint64 nonce, string memory name, address payable target, uint64 _amount, uint64 fromChainId, uint8 decimal, bytes memory signature) external { 
        require(_amount > 0, "Amount must be greater than 0");
        require(magic.length == 8,'magic must = 8');
        require(signature.length == 65,'signature must = 65');
    
        bytes memory str = abi.encodePacked(magic, nonce, name,target,_amount,fromChainId, uint64(block.chainid));
        bytes32 hashmsg = keccak256(str);
        require(done[hashmsg]==0,"already done");

        address tmp = recover(hashmsg,signature);
        require(tmp==minter, "invalid minter");
    
        if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked(natinveName))) {
            uint256 amount = convertBetweenDecimals(_amount,decimal,18);

            // 检查风控策略
            // if (risk.approve(amount,name,target)){
                require(target.send(amount),"Transfer failed");
                emit TokenWithdrawed("native", address(0), target, amount);
            // }else{
                // waitingList[hashmsg] = Application(name,target, amount, address(0));
                // emit WaitingApp(hashmsg,"native", address(0), target, amount);
            // }

            
        }else{
            address _token = tokenNames[name];
            require(_token != address(0), "Invalid token address");
           
            uint8 tokenDecimal = tokenDecimals[name];
            uint256 amount = convertBetweenDecimals(_amount,decimal,tokenDecimal);

             // 检查风控策略
            // if (risk.approve(convertBetweenDecimals(_amount,decimal,targetDecimal),name,target)){
                IERC20 token = IERC20(_token);
                require(token.transfer(target, amount), "Transfer failed");
                emit TokenWithdrawed(name,_token, target, amount);
            // }else{
                // waitingList[hashmsg] = Application(name,target, amount, _token);
                // emit WaitingApp(hashmsg,name,_token, target, amount);
            // }
            
        }  

        
        done[hashmsg] = 1; // 防止重放
    }

    // 增加流动性
    function addLiquity(string memory name, uint256 amount) external{
        require(amount>0, "amount must >0");

        address _token = tokenNames[name];
        require(_token != address(0), "Invalid token name");
        
        IERC20 token = IERC20(_token);
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        liq[msg.sender][name]+=amount;

    }

    // 减少流动性
    function delLiquity(string memory name, uint256 amount) external{
        require(amount>0, "amount must >0");
        require(liq[msg.sender][name]>amount, "not enough liq");

        address _token = tokenNames[name];
        require(_token != address(0), "Invalid token name");
        
        IERC20 token = IERC20(_token);
        require(token.transfer(msg.sender, amount), "Transfer failed");

        liq[msg.sender][name]-=amount;
    }

    function queryLiquity(string memory name, address owner) external view returns (uint256){
        address _token = tokenNames[name];
        require(_token != address(0), "Invalid token name");
        

        return liq[owner][name];
    }
   
    function approve(bytes32 id)external{
        require(msg.sender == approver,"no auth fo approve");

        Application memory app = waitingList[id];
        require(app.amount>0,"no such application");

        string memory name = app.name;
        address payable target = app.target;
        uint256 amount = app.amount;
        address _token = app.token;

        if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("native"))) {
            require(target.send(amount),"Transfer failed");
            emit TokenWithdrawApproved("native", address(0), target, amount);
        }else{
            IERC20 token = IERC20(_token);
            require(token.transfer(target, amount), "Transfer failed");
            emit TokenWithdrawApproved(name,_token, target, amount);
        }

        delete waitingList[id];
    }


   
   // mixchain 上给钱
    // function mintToken(bytes memory magic, uint64 nonce, string memory name, address payable target, uint256 _amount, uint256 chainId, uint8 decimals, bytes memory signature) external { 
    //     require(_amount > 0, "Amount must be greater than 0");
    //     require(signature.length == 65,'signature must = 65');
    //     require(magic.length == 8,'magic must = 8');

    //     bytes memory str = abi.encodePacked(magic,nonce,name,target,_amount,chainId,decimals);
    //     bytes32 hashmsg = keccak256(str);


    //     address tmp = recover(hashmsg,signature);
    //     require(tmp==minter, "invalid minter");
    
        
    //     //uint256 amount = convertBetweenDecimals(_amount,decimals,tokenDecimal);

    //     if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("sol"))){
    //         // transfer sol
            
    //     }else if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("native"))) {
    //         // 处理 eth、bnb
    //         address _token = nativeMappings[chainId];
    //         require(_token != address(0), "Invalid token address");

    //         IERC20 token = IERC20(_token);
    //         require(token.transfer(target, _amount), "Transfer failed");
    //     }else{
    //         // 处理 usdt、usdc、mixtoken
    //         address _token = tokenNames[name];
    //         require(_token != address(0), "Invalid token address");

    //         IERC20 token = IERC20(_token);
    //         require(token.transfer(target, _amount), "Transfer failed");
    //     }  
    // }

    function recover(bytes32 hashmsg, bytes memory signedString) private pure returns (address)
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

    function getMinter() external view returns (address){
        return minter;
    }

    // 在任意两个精度之间转换
    function convertBetweenDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) public pure returns (uint256) {
        if (fromDecimals == toDecimals) return amount;
        
        if (fromDecimals < toDecimals) {
            // 放大精度
            return amount * (10 ** (toDecimals - fromDecimals));
        } else {
            // 减小精度
            return amount / (10 ** (fromDecimals - toDecimals));
        }
    }

    struct Application{
        string  name;
        address payable target; 
        uint256 amount;
        address token;
    }
}
