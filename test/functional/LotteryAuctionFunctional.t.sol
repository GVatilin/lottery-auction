// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {BaseTest} from "../BaseTest.t.sol";
import {LotteryRoom} from "../../src/LotteryRoom.sol";
import {Config} from "../../script/Config.s.sol";
import {DeployScript} from "../../script/Deploy.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract LotteryAuctionTest is BaseTest {
    address vrfCoordinatorV2_5;
    uint256 public constant LINK_BALANCE = 10 ether;

    function setUp() external {
        DeployScript deployer = new DeployScript();
        (lotteryAuction, config) = deployer.run();
        vm.deal(PLAYER, STARTING_USER_BALANCE);

        Config.NetworkConfig memory networkConfig = config.getConfig();
        baseFee = networkConfig.baseFee;
        vrfCoordinatorV2_5 = networkConfig.vrfCoordinatorV2_5;
    }

    function testFulfillRandomWordsFinishesAuctionAndCreditsWinner() public {
        _createFunctionalRoomWithFourPlayers(0, "single-room-");
        _skipDefaultInterval();
        lotteryAuction.performUpkeep(abi.encode(0));

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123;
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5)
            .fulfillRandomWordsWithOverride(1, address(lotteryAuction), randomWords);

        address winner = lotteryAuction.getPlayer(0, 0);
        (,,,, uint256 prize) = lotteryAuction.getRoom(0);
        _skipDefaultInterval();
        lotteryAuction.performUpkeep(abi.encode(0));

        randomWords[0] = 0;
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5)
            .fulfillRandomWordsWithOverride(2, address(lotteryAuction), randomWords);

        vm.prank(winner);
        assertEq(lotteryAuction.getBalance(), prize);

        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__RoomNotFound.selector, 0));
        lotteryAuction.getRoom(0);
    }

    function testTwoRoomsCompleteIndependentlyAndWinnersWithdraw() public skipFork {
        _createFunctionalRoomWithFourPlayers(0, "room-zero-");
        _skipDefaultInterval();

        lotteryAuction.performUpkeep(_getFunctionalUpkeepData(0)); // requestId 1

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 111;
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5)
            .fulfillRandomWordsWithOverride(1, address(lotteryAuction), randomWords);

        address winnerZero = lotteryAuction.getPlayer(0, 0);
        _assertFunctionalAuctionRoom(0);

        _createFunctionalRoomWithFourPlayers(1, "room-one-");
        (LotteryRoom.LotteryState roomOneState,,,,) = lotteryAuction.getRoom(1);
        assertEq(uint256(roomOneState), uint256(LotteryRoom.LotteryState.OPEN));

        vm.prank(winnerZero);
        lotteryAuction.fundAuction{value: 1 ether}(0);
        (,,,, uint256 roomZeroPrize) = lotteryAuction.getRoom(0);
        assertEq(roomZeroPrize, baseFee * 4 + 1 ether);

        _skipDefaultInterval();

        lotteryAuction.performUpkeep(abi.encode(0)); // requestId 2
        randomWords[0] = 0;
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5)
            .fulfillRandomWordsWithOverride(2, address(lotteryAuction), randomWords);

        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__RoomNotFound.selector, 0));
        lotteryAuction.getRoom(0);

        uint256 roomOneInterval;
        (roomOneState,,, roomOneInterval,) = lotteryAuction.getRoom(1);
        assertEq(uint256(roomOneState), uint256(LotteryRoom.LotteryState.OPEN));
        assertEq(roomOneInterval, DEFAULT_INTERVAL);

        lotteryAuction.performUpkeep(_getFunctionalUpkeepData(1)); // requestId 3
        randomWords[0] = 222;
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5)
            .fulfillRandomWordsWithOverride(3, address(lotteryAuction), randomWords);

        address winnerOne = lotteryAuction.getPlayer(1, 0);
        _assertFunctionalAuctionRoom(1);

        vm.prank(winnerOne);
        lotteryAuction.fundAuction{value: 2 ether}(1);
        (,,,, uint256 roomOnePrize) = lotteryAuction.getRoom(1);
        assertEq(roomOnePrize, baseFee * 4 + 2 ether);

        _skipDefaultInterval();
        lotteryAuction.performUpkeep(_getFunctionalUpkeepData(1)); // requestId 4
        randomWords[0] = 0;
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5)
            .fulfillRandomWordsWithOverride(4, address(lotteryAuction), randomWords);

        vm.prank(winnerZero);
        assertEq(lotteryAuction.getBalance(), roomZeroPrize);
        vm.prank(winnerOne);
        assertEq(lotteryAuction.getBalance(), roomOnePrize);

        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__RoomNotFound.selector, 1));
        lotteryAuction.getRoom(1);

        vm.prank(winnerZero);
        lotteryAuction.withdraw();
        vm.prank(winnerOne);
        lotteryAuction.withdraw();

        assertEq(address(lotteryAuction).balance, 0);
    }

    function _createFunctionalRoomWithFourPlayers(uint256 roomId, string memory prefix) internal {
        address owner = makeAddr(string.concat(prefix, "0"));
        hoax(owner, STARTING_USER_BALANCE);
        lotteryAuction.createRoom{value: baseFee}(DEFAULT_INTERVAL);

        for (uint256 i = 1; i < 4; ++i) {
            address player = makeAddr(string.concat(prefix, vm.toString(i)));
            hoax(player, STARTING_USER_BALANCE);
            lotteryAuction.enterRoom{value: baseFee}(roomId);
        }
    }

    function _getFunctionalUpkeepData(uint256 expectedRoomId) internal view returns (bytes memory performData) {
        (bool upkeepNeeded, bytes memory data) = lotteryAuction.checkUpkeep("");
        assertTrue(upkeepNeeded);
        assertEq(abi.decode(data, (uint256)), expectedRoomId);
        return data;
    }

    function _assertFunctionalAuctionRoom(uint256 roomId) internal view {
        (LotteryRoom.LotteryState state,, uint256 playersCount,,) = lotteryAuction.getRoom(roomId);
        assertEq(uint256(state), uint256(LotteryRoom.LotteryState.AUCTION));
        assertEq(playersCount, 2);
    }
}
