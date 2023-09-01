//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NARStablecoin is ERC20Burnable, Ownable {
    error NAR_mustBeMoreThanZero();
    error NAR_notEnoughBalance();
    error NAR_addressInvalid();

    constructor() ERC20("NINAR", "NAR") Ownable(0x2ae5013487cf7aa6e2000fe1881dD7D295f34E85){}

    function burn(uint256 _amount) public override onlyOwner {
        if (_amount <= 0) {
            revert NAR_mustBeMoreThanZero();
        }
        uint256 balance = balanceOf(msg.sender);

        if (balance <= _amount) {
            revert NAR_notEnoughBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert NAR_addressInvalid();
        }
        if (_amount <= 0) {
            revert NAR_mustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
