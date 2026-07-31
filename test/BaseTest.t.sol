// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {LotteryAuction} from "../src/LotteryAuction.sol";
import {Config} from "../script/Config.s.sol";

abstract contract BaseTest is Test {
    LotteryAuction internal lotteryAuction;
    Config public config;

    address internal PLAYER = makeAddr("player");

    uint256 baseFee;
    uint256 internal constant DEFAULT_INTERVAL = 60;
    uint256 internal constant STARTING_USER_BALANCE = 5 ether;

    modifier createRoom() {
        vm.prank(PLAYER);
        lotteryAuction.createRoom{value: baseFee}(DEFAULT_INTERVAL);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function _enterSecondPlayer(uint256 roomId) internal returns (address) {
        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(roomId);

        return secondPlayer;
    }

    function _skipDefaultInterval() internal {
        vm.warp(block.timestamp + DEFAULT_INTERVAL + 1);
        vm.roll(block.number + 1);
    }
}
