// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {BaseTest} from "../BaseTest.t.sol";
import {LotteryAuction} from "../../src/LotteryAuction.sol";
import {LotteryRoom} from "../../src/LotteryRoom.sol";
import {Config} from "../../script/Config.s.sol";
import {LinkToken} from "../../script/mocks/LinkToken.sol";
import {DeployScript} from "../../script/Deploy.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract LotteryAuctionTest is BaseTest {
    uint256 subscriptionId;
    bytes32 gasLane;
    uint32 gasLimit;
    address vrfCoordinatorV2_5;
    LinkToken link;
    uint256 public constant LINK_BALANCE = 10 ether;

    function setUp() external {
        DeployScript deployer = new DeployScript();
        (lotteryAuction, config) = deployer.run();
        vm.deal(PLAYER, STARTING_USER_BALANCE);

        Config.NetworkConfig memory networkConfig = config.getConfig();
        subscriptionId = networkConfig.subscriptionId;
        gasLane = networkConfig.gasLane;
        baseFee = networkConfig.baseFee;
        gasLimit = networkConfig.gasLimit;
        vrfCoordinatorV2_5 = networkConfig.vrfCoordinatorV2_5;
        link = LinkToken(networkConfig.link);
    }

    // **************************  checkUpkeep  **************************
    function testCheckUpkeepReturnsTrueIfAllConditionsForFirstRoundCorrect() public createRoom {
        _enterSecondPlayer(0);
        _skipDefaultInterval();

        (bool upkeepNeeded, bytes memory performData) = lotteryAuction.checkUpkeep("");

        uint256 roomId = abi.decode(performData, (uint256));

        assertTrue(upkeepNeeded);
        assertEq(roomId, 0);
    }

    function testCheckUpkeepReturnsFalseIfNotEnoughTimeHasPassed() public createRoom {
        _enterSecondPlayer(0);

        (bool upkeepNeeded,) = lotteryAuction.checkUpkeep("");

        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepReturnsFalseIfRoomCalculating() public createRoom {
        _enterSecondPlayer(0);
        _skipDefaultInterval();

        lotteryAuction.performUpkeep(abi.encode(0));
        (LotteryRoom.LotteryState state,,,,) = lotteryAuction.getRoom(0);

        (bool upkeepNeeded,) = lotteryAuction.checkUpkeep("");

        assertEq(uint256(state), uint256(LotteryRoom.LotteryState.CALCULATING));
        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepReturnsFalseIfRoomAwaiting() public createRoom {
        _skipDefaultInterval();

        (LotteryRoom.LotteryState state,,,,) = lotteryAuction.getRoom(0);
        (bool upkeepNeeded,) = lotteryAuction.checkUpkeep("");

        assertEq(uint256(state), uint256(LotteryRoom.LotteryState.AWAITING));
        assertEq(upkeepNeeded, false);
    }

    // **************************  performUpkeep  **************************
    function testPerformUpkeepRevertWithWrongRoomId() public {
        uint256 wrongRoomId = 999;

        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__RoomNotFound.selector, wrongRoomId));
        lotteryAuction.performUpkeep(abi.encode(wrongRoomId));
    }

    function testPerformUpkeepRevertIfCheckUpkeepFalse() public createRoom {
        _enterSecondPlayer(0);

        vm.expectRevert(LotteryAuction.LotteryAuction__UpkeepNotNeeded.selector);
        lotteryAuction.performUpkeep(abi.encode(0));
    }

    function testPerformUpkeepUpdatesStateToCalculating() public createRoom {
        _enterSecondPlayer(0);
        _skipDefaultInterval();

        lotteryAuction.performUpkeep(abi.encode(0));

        (LotteryRoom.LotteryState state,,,,) = lotteryAuction.getRoom(0);
        assertEq(uint256(state), uint256(LotteryRoom.LotteryState.CALCULATING));
    }

    function testPerformUpkeepUpdatesStateToCalculatingAuction() public {
        _skipToAuction();

        (LotteryRoom.LotteryState auctionState,,,,) = lotteryAuction.getRoom(0);
        assertEq(uint256(auctionState), uint256(LotteryRoom.LotteryState.AUCTION));

        _skipDefaultInterval();
        lotteryAuction.performUpkeep(abi.encode(0));

        (LotteryRoom.LotteryState state,,,,) = lotteryAuction.getRoom(0);
        assertEq(uint256(state), uint256(LotteryRoom.LotteryState.CALCULATING_AUCTION));
    }

    // **************************  fundAuction  **************************
    function testFundAuction() public {
        _skipToAuction();
        address auctionPlayer = lotteryAuction.getPlayer(0, 0);
        uint256 additionalBet = 1 ether;
        uint256 playerBalanceBefore = auctionPlayer.balance;
        uint256 contractBalanceBefore = address(lotteryAuction).balance;
        (LotteryRoom.LotteryState stateBefore,,,, uint256 betsAmountBefore) = lotteryAuction.getRoom(0);

        vm.prank(auctionPlayer);
        lotteryAuction.fundAuction{value: additionalBet}(0);

        (LotteryRoom.LotteryState stateAfter,, uint256 playersCount,, uint256 betsAmountAfter) =
            lotteryAuction.getRoom(0);

        assertEq(uint256(stateBefore), uint256(LotteryRoom.LotteryState.AUCTION));
        assertEq(uint256(stateAfter), uint256(LotteryRoom.LotteryState.AUCTION));
        assertEq(playersCount, 1);
        assertEq(betsAmountAfter, betsAmountBefore + additionalBet);
        assertEq(address(lotteryAuction).balance, contractBalanceBefore + additionalBet);
        assertEq(auctionPlayer.balance, playerBalanceBefore - additionalBet);
    }

    function testCantFundAuctionIfNotMember() public {
        _skipToAuction();

        address thirdPlayer = makeAddr("thirdPlayer");
        hoax(thirdPlayer, STARTING_USER_BALANCE);

        vm.expectRevert(LotteryRoom.LotteryRoom__NotRoomMember.selector);
        lotteryAuction.fundAuction{value: 1 ether}(0);
    }

    function testCantFundAuctionIfNotAuctionState() public createRoom {
        vm.expectRevert(LotteryAuction.LotteryAuction__AuctionUnavailable.selector);

        vm.prank(PLAYER);
        lotteryAuction.fundAuction{value: 1 ether}(0);
    }

    function testCantFundAuctionIfTimeHasPassed() public {
        _skipToAuction();
        address auctionPlayer = lotteryAuction.getPlayer(0, 0);
        _skipDefaultInterval();

        vm.expectRevert(LotteryAuction.LotteryAuction__AuctionIsClosed.selector);

        vm.prank(auctionPlayer);
        lotteryAuction.fundAuction{value: 1 ether}(0);
    }

    function testCantFundAuctionWithZeroValue() public {
        _skipToAuction();
        address auctionPlayer = lotteryAuction.getPlayer(0, 0);

        vm.expectRevert(LotteryAuction.LotteryAuction__CantBetZero.selector);

        vm.prank(auctionPlayer);
        lotteryAuction.fundAuction(0);
    }

    function testEmitsEventOnFundedAuction() public {
        _skipToAuction();
        address auctionPlayer = lotteryAuction.getPlayer(0, 0);
        uint256 additionalBet = 1 ether;

        vm.expectEmit(true, true, false, false, address(lotteryAuction));
        emit LotteryAuction.AuctionFunded(0, auctionPlayer);

        vm.prank(auctionPlayer);
        lotteryAuction.fundAuction{value: additionalBet}(0);

        (,,,, uint256 betsAmount) = lotteryAuction.getRoom(0);
        assertEq(betsAmount, baseFee * 2 + additionalBet);
    }

    // **************************  withdraw  **************************
    function testWithdraw() public skipFork {
        _skipToAuction();
        address winner = lotteryAuction.getPlayer(0, 0);
        (,,,, uint256 prize) = lotteryAuction.getRoom(0);

        _skipDefaultInterval();
        lotteryAuction.performUpkeep(abi.encode(0));
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fulfillRandomWords(2, address(lotteryAuction));

        vm.startPrank(winner);
        uint256 winningsBefore = lotteryAuction.getBalance();
        uint256 winnerBalanceBefore = winner.balance;
        uint256 contractBalanceBefore = address(lotteryAuction).balance;

        lotteryAuction.withdraw();
        uint256 winningsAfter = lotteryAuction.getBalance();
        vm.stopPrank();

        assertEq(winningsBefore, prize);
        assertEq(winningsAfter, 0);
        assertEq(winner.balance, winnerBalanceBefore + prize);
        assertEq(address(lotteryAuction).balance, contractBalanceBefore - prize);
    }

    function testCantWithdrawWithZeroBalance() public {
        vm.expectRevert(LotteryAuction.LotteryAuction__ZeroBalance.selector);

        vm.prank(PLAYER);
        lotteryAuction.withdraw();
    }

    // **************************  fulfillRandomWords  **************************
    function testCantCallFulfillRandomWordsBeforePerformUpkeep() public skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fulfillRandomWords(0, address(lotteryAuction));

        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fulfillRandomWords(1, address(lotteryAuction));
    }

    function testFulfillRandomWordsSelectsHalfOfPlayers() public skipFork {
        _requestFirstRoundWithFourPlayers();
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123;

        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5)
            .fulfillRandomWordsWithOverride(1, address(lotteryAuction), randomWords);

        (LotteryRoom.LotteryState state, uint256 lastTimestamp, uint256 playersCount,, uint256 betsAmount) =
            lotteryAuction.getRoom(0);
        address firstSurvivor = lotteryAuction.getPlayer(0, 0);
        address secondSurvivor = lotteryAuction.getPlayer(0, 1);

        assertEq(uint256(state), uint256(LotteryRoom.LotteryState.AUCTION));
        assertEq(lastTimestamp, block.timestamp);
        assertEq(playersCount, 2);
        assertEq(betsAmount, baseFee * 4);
        assertNotEq(firstSurvivor, address(0));
        assertNotEq(secondSurvivor, address(0));
        assertNotEq(firstSurvivor, secondSurvivor);
    }

    function testFulfillRandomWordsEmitsLotteryAuctionEnded() public skipFork {
        _requestFirstRoundWithFourPlayers();
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123;
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5)
            .fulfillRandomWordsWithOverride(1, address(lotteryAuction), randomWords);

        _skipDefaultInterval();
        lotteryAuction.performUpkeep(abi.encode(0));

        randomWords[0] = 0;
        vm.expectEmit(true, false, false, false, address(lotteryAuction));
        emit LotteryAuction.LotteryAuctionEnded(0);
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5)
            .fulfillRandomWordsWithOverride(2, address(lotteryAuction), randomWords);
    }

    // **************************  utils  **************************
    function _requestFirstRoundWithFourPlayers() internal createRoom {
        _enterSecondPlayer(0);

        address thirdPlayer = makeAddr("thirdPlayer");
        hoax(thirdPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);

        address fourthPlayer = makeAddr("fourthPlayer");
        hoax(fourthPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);

        _skipDefaultInterval();
        lotteryAuction.performUpkeep(abi.encode(0));
    }

    function _skipToAuction() internal createRoom skipFork {
        _enterSecondPlayer(0);
        _skipDefaultInterval();

        lotteryAuction.performUpkeep(abi.encode(0));
        VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fulfillRandomWords(1, address(lotteryAuction));
    }
}
