// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {LotteryAuction} from "../src/LotteryAuction.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract Subscription {
    LotteryAuction private immutable i_lotteryAuction;

    constructor(
        address vrfCoordinatorV2_5,
        bytes32 gasLane,
        uint256 baseFee,
        uint32 gasLimit,
        uint256 maxPlayers,
        uint96 fundAmount,
        address finalOwner
    ) {
        uint256 subId = _createAndFund(vrfCoordinatorV2_5, fundAmount);

        LotteryAuction auction = new LotteryAuction(subId, gasLane, baseFee, gasLimit, vrfCoordinatorV2_5, maxPlayers);

        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).addConsumer(subId, address(auction));
        auction.transferOwnership(finalOwner);

        i_lotteryAuction = auction;
    }

    function getLotteryAuction() external view returns (LotteryAuction) {
        return i_lotteryAuction;
    }

    function _createAndFund(address vrfCoordinatorV2_5, uint96 fundAmount) private returns (uint256 subId) {
        VRFCoordinatorV2_5Mock coordinator = VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5);
        subId = coordinator.createSubscription();
        coordinator.fundSubscription(subId, fundAmount);
    }
}