// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Script} from "forge-std/Script.sol";
import {LotteryAuction} from "../src/LotteryAuction.sol";
import {Config} from "./Config.s.sol";
import {Subscription} from "./Subscriptions.s.sol";

contract DeployScript is Script {
    function run() external {
        Config config = new Config();
        Config.NetworkConfig memory networkConfig = config.getConfig();
        uint256 subId = networkConfig.subscriptionId;

        if (subId == 0) {
            Subscription subscription = new Subscription();
            subId = subscription.createAndFund(
                subId, networkConfig.vrfCoordinatorV2_5, networkConfig.link, networkConfig.account
            );
        }

        vm.startBroadcast(networkConfig.account);

        LotteryAuction lotteryAuction = new LotteryAuction(
            subId,
            networkConfig.gasLane,
            networkConfig.baseFee,
            networkConfig.gasLimit,
            networkConfig.vrfCoordinatorV2_5,
            networkConfig.maxPlayers
        );

        VRFCoordinatorV2_5Mock(networkConfig.vrfCoordinatorV2_5).addConsumer(subId, address(lotteryAuction));

        vm.stopBroadcast();
    }
}
