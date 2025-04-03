// SPDX-License-Identifier: MIT
// 0x3F6174a796E2b38fe0dBF45461A1a7195D98d774
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyToken is ERC20 {
    uint8 private constant DECIMALS = 18;
    uint256 private constant INITIAL_SUPPLY = 1_000_000; // 100万代币

    constructor() ERC20("myToken", "mtk") {
        // 铸造初始代币给合约部署者
        // 需要考虑 decimals，所以实际铸造数量为: INITIAL_SUPPLY * 10^DECIMALS
        _mint(msg.sender, INITIAL_SUPPLY * 10**DECIMALS);
        //_mint(,INITIAL_SUPPLY * 10**DECIMALS);
    }

    function airdrop() public {
         _mint(msg.sender, 10 * 10**DECIMALS);
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
