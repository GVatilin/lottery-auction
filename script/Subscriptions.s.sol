// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.36;

import {Script} from "forge-std/Script.sol";
import {Config, Constants} from "./Config.s.sol";
import {LotteryAuction} from "../src/LotteryAuction.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract Subscription is Constants, Script {
    uint96 public constant FUND_AMOUNT = 1 ether;

    function createAndFund(uint256 subId, address vrfCoordinatorV2_5, address link, address account)
        public
        returns (uint256)
    {
        if (subId == 0) {
            vm.startBroadcast(account);
            subId = VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).createSubscription();
            vm.stopBroadcast();
        }

        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast(account);
            VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fundSubscription(subId, FUND_AMOUNT);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(account);
            LinkToken(link).transferAndCall(vrfCoordinatorV2_5, FUND_AMOUNT, abi.encode(subId));
            vm.stopBroadcast();
        }

        return subId;
    }

    function createAndFundUsingConfig() public returns (uint256 newSubId) {
        Config config = new Config();
        Config.NetworkConfig memory networkConfig = config.getConfig();
        uint256 subId = networkConfig.subscriptionId;
        address vrfCoordinatorV2_5 = networkConfig.vrfCoordinatorV2_5;
        address link = networkConfig.link;
        address account = networkConfig.account;

        return createAndFund(subId, vrfCoordinatorV2_5, link, account);
    }

    function run() external {
        createAndFundUsingConfig();
    }
}
