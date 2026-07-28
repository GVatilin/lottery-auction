// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {LotteryAuction} from "../src/LotteryAuction.sol";
import {LotteryRoom} from "../src/LotteryRoom.sol";
import {Config} from "../script/Config.s.sol";
import {LinkToken} from "./mocks/LinkToken.sol";
import {DeployScript} from "../script/Deploy.s.sol";

contract LotteryAuctionTest is Test {
    LotteryAuction public lotteryAuction;
    Config public config;

    uint256 subscriptionId;
    bytes32 gasLane;
    uint256 baseFee;
    uint32 gasLimit;
    address vrfCoordinatorV2_5;
    LinkToken link;
    uint256 maxPlayers;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 5 ether;
    uint256 public constant LINK_BALANCE = 10 ether;
    uint256 public constant DEFAULT_INTERVAL = 60;

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
        maxPlayers = networkConfig.maxPlayers;
    }

    modifier createRoom() {
        vm.prank(PLAYER);
        lotteryAuction.createRoom{value: baseFee}(DEFAULT_INTERVAL);
        _;
    }

    modifier startLottery() {
        address secondPlayer = makeAddr("secondPlayer");
        hoax(secondPlayer, STARTING_USER_BALANCE);
        lotteryAuction.enterRoom{value: baseFee}(0);

        vm.warp(block.timestamp + DEFAULT_INTERVAL + 1);
        vm.roll(block.number + 1);

        lotteryAuction.performUpkeep(abi.encode(0));
        _;
    }

    function testCreateRoom() public createRoom {
        (LotteryRoom.LotteryState state,, uint256 playersCount, uint256 interval, uint256 betsAmount) =
            lotteryAuction.getRoom(0);
        address player = lotteryAuction.getPlayer(0, 0);

        assert(state == LotteryRoom.LotteryState.AWAITING);
        assert(playersCount == 1);
        assert(interval == DEFAULT_INTERVAL);
        assert(betsAmount == baseFee);
        assert(player == PLAYER);
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

        assert(state == LotteryRoom.LotteryState.OPEN);
        assert(playersCount == 2);
        assert(interval == DEFAULT_INTERVAL);
        assert(betsAmount == baseFee * 2);
        assert(expectedPlayer == secondPlayer);
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

        assert(state == LotteryRoom.LotteryState.AWAITING);
        assert(playersCount == 1);
        assert(interval == DEFAULT_INTERVAL);
        assert(betsAmount == baseFee);
        assert(player == secondPlayer);
        assert(PLAYER.balance == balanceBefore + baseFee);
    }

    function testLeaveAwaitingRoom() public createRoom {
        vm.startPrank(PLAYER);

        lotteryAuction.leaveRoom(0);

        vm.expectRevert(abi.encodeWithSelector(LotteryRoom.LotteryRoom__RoomNotFound.selector, 0));
        lotteryAuction.enterRoom{value: baseFee}(0);

        vm.stopPrank();
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
}
