// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {BaseTest} from "../BaseTest.t.sol";
import {LotteryAuction} from "../../src/LotteryAuction.sol";
import {LotteryRoom} from "../../src/LotteryRoom.sol";
import {Config} from "../../script/Config.s.sol";
import {LinkToken} from "../../script/mocks/LinkToken.sol";
import {DeployScript} from "../../script/Deploy.s.sol";

contract LotteryRoomTest is BaseTest {
    uint256 maxPlayers;

    function setUp() external {
        DeployScript deployer = new DeployScript();
        (lotteryAuction, config) = deployer.run();
        vm.deal(PLAYER, STARTING_USER_BALANCE);

        Config.NetworkConfig memory networkConfig = config.getConfig();
        baseFee = networkConfig.baseFee;
        maxPlayers = networkConfig.maxPlayers;
    }

    modifier startLottery() {
        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);

        _skipDefaultInterval();

        lotteryAuction.performUpkeep(abi.encode(0));
        _;
    }

    function testCreateRoom() public createRoom {
        (LotteryRoom.LotteryState state,, uint256 playersCount, uint256 interval, uint256 betsAmount) =
            lotteryAuction.getRoom(0);
        address player = lotteryAuction.getPlayer(0, 0);

        assertEq(uint256(state), uint256(LotteryRoom.LotteryState.AWAITING));
        assertEq(playersCount, 1);
        assertEq(interval, DEFAULT_INTERVAL);
        assertEq(betsAmount, baseFee);
        assertEq(player, PLAYER);
    }

    function testCantCreateRoomWithoutFee() public {
        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__IncorrectBaseFee.selector, baseFee, 0));

        vm.prank(PLAYER);
        lotteryAuction.createRoom(DEFAULT_INTERVAL);
    }

    function testCantCreateRoomWithIncorrectFee() public {
        uint256 incorrectBaseFee = baseFee * 2;

        vm.expectRevert(
            abi.encodeWithSelector(LotteryRoom.LotteryRoom__IncorrectBaseFee.selector, baseFee, incorrectBaseFee)
        );

        vm.prank(PLAYER);
        lotteryAuction.createRoom{value: incorrectBaseFee}(DEFAULT_INTERVAL);
    }

    function testEmitsEventOnCreationRoom() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, true, false, false, address(lotteryAuction));
        emit LotteryRoom.RoomCreated(0, PLAYER);
        lotteryAuction.createRoom{value: baseFee}(DEFAULT_INTERVAL);
    }

    function testEnterRoom() public createRoom {
        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);

        (LotteryRoom.LotteryState state,, uint256 playersCount, uint256 interval, uint256 betsAmount) =
            lotteryAuction.getRoom(0);
        address expectedPlayer = lotteryAuction.getPlayer(0, 1);

        assertEq(uint256(state), uint256(LotteryRoom.LotteryState.OPEN));
        assertEq(playersCount, 2);
        assertEq(interval, DEFAULT_INTERVAL);
        assertEq(betsAmount, baseFee * 2);
        assertEq(expectedPlayer, secondPlayer);
    }

    function testCantEnterRoomWithoutFee() public createRoom {
        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__IncorrectBaseFee.selector, baseFee, 0));

        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom(0);
    }

    function testCantEnterRoomWithIncorrectFee() public createRoom {
        uint256 incorrectBaseFee = baseFee * 2;

        vm.expectRevert(
            abi.encodeWithSelector(LotteryRoom.LotteryRoom__IncorrectBaseFee.selector, baseFee, incorrectBaseFee)
        );

        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: incorrectBaseFee}(0);
    }

    function testEmitsEventOnEnteranceRoom() public createRoom {
        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);

        vm.expectEmit(true, true, false, false, address(lotteryAuction));
        emit LotteryRoom.RoomEntered(0, secondPlayer);
        lotteryAuction.enterRoom{value: baseFee}(0);
    }

    function testCantEnterToNotExistingRoom() public {
        vm.prank(PLAYER);

        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__RoomNotFound.selector, 0));
        lotteryAuction.enterRoom{value: baseFee}(0);
    }

    function testCantEnterRoomTwice() public createRoom {
        vm.expectRevert(LotteryRoom.LotteryRoom__CantEnterRoomTwice.selector);
        vm.prank(PLAYER);
        lotteryAuction.enterRoom{value: baseFee}(0);
    }

    function testCantEnterClosedRoom() public createRoom startLottery {
        address newPlayer = makeAddr("newPlayer");
        hoax(newPlayer, STARTING_USER_BALANCE);

        vm.expectRevert(
            abi.encodeWithSelector(
                LotteryRoom.LotteryRoom__RoomMustBeOpen.selector, LotteryRoom.LotteryState.CALCULATING
            )
        );
        lotteryAuction.enterRoom{value: baseFee}(0);
    }

    function testCantEnterRoomWithMaxPlayers() public createRoom {
        for (uint256 i = 0; i < maxPlayers - 1; ++i) {
            address tmpPlayer = makeAddr(vm.toString(i));
            hoax(tmpPlayer, STARTING_USER_BALANCE);
            lotteryAuction.enterRoom{value: baseFee}(0);
        }

        address newPlayer = makeAddr("newPlayer");
        hoax(newPlayer, STARTING_USER_BALANCE);

        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__MaxPlayersInRoom.selector, maxPlayers));
        lotteryAuction.enterRoom{value: baseFee}(0);
    }

    function testLeaveOpenRoom() public createRoom {
        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);

        uint256 balanceBefore = PLAYER.balance;

        vm.prank(PLAYER);
        lotteryAuction.leaveRoom(0);

        (LotteryRoom.LotteryState state,, uint256 playersCount, uint256 interval, uint256 betsAmount) =
            lotteryAuction.getRoom(0);
        address player = lotteryAuction.getPlayer(0, 0);

        assertEq(uint256(state), uint256(LotteryRoom.LotteryState.AWAITING));
        assertEq(playersCount, 1);
        assertEq(interval, DEFAULT_INTERVAL);
        assertEq(betsAmount, baseFee);
        assertEq(player, secondPlayer);
        assertEq(PLAYER.balance, balanceBefore + baseFee);
    }

    function testLeaveAwaitingRoom() public createRoom {
        uint256 balanceBefore = PLAYER.balance;

        vm.startPrank(PLAYER);

        lotteryAuction.leaveRoom(0);
        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__RoomNotFound.selector, 0));
        lotteryAuction.enterRoom{value: baseFee}(0);

        vm.stopPrank();

        assertEq(PLAYER.balance, balanceBefore + baseFee);
    }

    function testCantLeaveIfNotRoomMember() public createRoom {
        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);

        vm.expectRevert(LotteryRoom.LotteryRoom__NotRoomMember.selector);
        lotteryAuction.leaveRoom(0);
    }

    function testCantLeaveIfRoomClosed() public createRoom startLottery {
        vm.prank(PLAYER);
        vm.expectRevert(LotteryRoom.LotteryRoom__CantLeaveRoomNow.selector);
        lotteryAuction.leaveRoom(0);
    }

    function testEmitsEventOnLeaveOpenRoom() public createRoom {
        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);

        vm.expectEmit(true, true, false, false, address(lotteryAuction));
        emit LotteryRoom.RoomLeft(0, PLAYER);
        vm.expectEmit(true, false, false, false, address(lotteryAuction));
        emit LotteryRoom.RoomWentToAwaiting(0);

        vm.prank(PLAYER);
        lotteryAuction.leaveRoom(0);
    }

    function testEmitsEventOnLeaveAwaitingRoom() public createRoom {
        vm.expectEmit(true, true, false, false, address(lotteryAuction));
        emit LotteryRoom.RoomLeft(0, PLAYER);
        vm.expectEmit(true, false, false, false, address(lotteryAuction));
        emit LotteryRoom.RoomDeleted(0);

        vm.prank(PLAYER);
        lotteryAuction.leaveRoom(0);
    }

    function testUpdatesPlayerIndexAfterSwapAndPop() public createRoom {
        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);

        vm.prank(PLAYER);
        lotteryAuction.leaveRoom(0);

        vm.prank(secondPlayer);
        lotteryAuction.leaveRoom(0);

        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__RoomNotFound.selector, 0));
        lotteryAuction.getRoom(0);
    }

    function testDeletesRoomFromMiddleAndUpdatesMovedRoomIndex() public {
        address roomZeroOwner = makeAddr("roomZeroOwner");
        address roomOneOwner = makeAddr("roomOneOwner");
        address roomTwoOwner = makeAddr("roomTwoOwner");

        hoax(roomZeroOwner, STARTING_USER_BALANCE);
        lotteryAuction.createRoom{value: baseFee}(DEFAULT_INTERVAL);
        hoax(roomOneOwner, STARTING_USER_BALANCE);
        lotteryAuction.createRoom{value: baseFee}(DEFAULT_INTERVAL);
        hoax(roomTwoOwner, STARTING_USER_BALANCE);
        lotteryAuction.createRoom{value: baseFee}(DEFAULT_INTERVAL);

        vm.prank(roomOneOwner);
        lotteryAuction.leaveRoom(1);

        (,, uint256 playersCount,,) = lotteryAuction.getRoom(2);
        assertEq(playersCount, 1);
        assertEq(lotteryAuction.getPlayer(2, 0), roomTwoOwner);

        vm.prank(roomTwoOwner);
        lotteryAuction.leaveRoom(2);

        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__RoomNotFound.selector, 2));
        lotteryAuction.getRoom(2);

        (,, playersCount,,) = lotteryAuction.getRoom(0);
        assertEq(playersCount, 1);
    }

    function testRoomStaysOpenWhenOneOfThreePlayersLeaves() public createRoom {
        address secondPlayer = makeAddr("secondPlayer");
        address thirdPlayer = makeAddr("thirdPlayer");

        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);
        hoax(thirdPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);

        vm.prank(PLAYER);
        lotteryAuction.leaveRoom(0);

        (LotteryRoom.LotteryState state,, uint256 playersCount,, uint256 betsAmount) = lotteryAuction.getRoom(0);
        assertEq(uint256(state), uint256(LotteryRoom.LotteryState.OPEN));
        assertEq(playersCount, 2);
        assertEq(betsAmount, baseFee * 2);
    }

    function testPlayerCanEnterAgainAfterLeaving() public createRoom {
        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);

        vm.prank(PLAYER);
        lotteryAuction.leaveRoom(0);

        vm.prank(PLAYER);
        lotteryAuction.enterRoom{value: baseFee}(0);

        (LotteryRoom.LotteryState state,, uint256 playersCount,, uint256 betsAmount) = lotteryAuction.getRoom(0);
        assertEq(uint256(state), uint256(LotteryRoom.LotteryState.OPEN));
        assertEq(playersCount, 2);
        assertEq(betsAmount, baseFee * 2);
        assertEq(lotteryAuction.getPlayer(0, 1), PLAYER);
    }

    function testContractBalanceAfterMultipleEntriesAndLeaves() public createRoom {
        address secondPlayer = makeAddr("secondPlayer");
        address thirdPlayer = makeAddr("thirdPlayer");

        assertEq(address(lotteryAuction).balance, baseFee);

        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);
        assertEq(address(lotteryAuction).balance, baseFee * 2);

        hoax(thirdPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);
        assertEq(address(lotteryAuction).balance, baseFee * 3);

        vm.prank(secondPlayer);
        lotteryAuction.leaveRoom(0);
        assertEq(address(lotteryAuction).balance, baseFee * 2);

        vm.prank(PLAYER);
        lotteryAuction.leaveRoom(0);
        assertEq(address(lotteryAuction).balance, baseFee);

        vm.prank(thirdPlayer);
        lotteryAuction.leaveRoom(0);
        assertEq(address(lotteryAuction).balance, 0);
    }

    function testConstructorRevertsWhenBaseFeeIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__InvalidBaseFee.selector, 0));
        new LotteryRoom(0, 50);
    }

    function testConstructorRevertsWhenMaxPlayersIsLessThanTwo() public {
        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__InvalidMaxPlayers.selector, 1));
        new LotteryRoom(1 ether, 1);
    }

    function testConstructorRevertsWhenMaxPlayersIsGreaterThanOneHundred() public {
        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__InvalidMaxPlayers.selector, 101));
        new LotteryRoom(1 ether, 101);
    }
}
