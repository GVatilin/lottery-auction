// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Script} from "forge-std/Script.sol";
import {LotteryAuction} from "../src/LotteryAuction.sol";
import {Config, Constants} from "./Config.s.sol";
import {Subscription} from "./Subscriptions.s.sol";

contract DeployScript is Constants, Script {
    error DeployScript__MissingSubscriptionId(uint256 chainId);

    function run() external returns (LotteryAuction, Config) {
        Config config = new Config();
        Config.NetworkConfig memory networkConfig = config.getConfig();

        if (block.chainid == LOCAL_CHAIN_ID) {
            LotteryAuction localLotteryAuction = _createAndFundLocalLotteryAuction(networkConfig);
            return (localLotteryAuction, config);
        }

        uint256 subId = networkConfig.subscriptionId;
        if (subId == 0) {
            revert DeployScript__MissingSubscriptionId(block.chainid);
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

        return (lotteryAuction, config);
    }

    function _createAndFundLocalLotteryAuction(Config.NetworkConfig memory networkConfig)
        private
        returns (LotteryAuction)
    {
        vm.startBroadcast(networkConfig.account);

        Subscription subscription = new Subscription(
            networkConfig.vrfCoordinatorV2_5,
            networkConfig.gasLane,
            networkConfig.baseFee,
            networkConfig.gasLimit,
            networkConfig.maxPlayers,
            LOCAL_FUND_AMOUNT,
            networkConfig.account
        );

        LotteryAuction localLotteryAuction = subscription.getLotteryAuction();
        localLotteryAuction.acceptOwnership();

        vm.stopBroadcast();

        return localLotteryAuction;
    }
}
