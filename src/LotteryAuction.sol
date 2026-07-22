// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

contract LotteryAuction is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    error LotteryAuction__IncorrectBaseFee();
    error LotteryAuction__CantLeaveRoomNow();
    error LotteryAuction__TransferFailed();
    error LotteryAuction__RoomNotFound();
    error LotteryAuction__NotRoomMember();
    error LotteryAuction__CantJoinTwice();
    error LotteryAuction__CantJoinNow();

    enum LotteryState {
        AWAITING,
        OPEN,
        AUCTION,
        CALCULATING
    }

    struct LotteryRoom {
        LotteryState state;
        mapping(address => uint256) playerToBet;
        uint256 lastTimestamp;
        uint32 playersCount;
    }

    // Chainlink
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;

    // Settings
    uint256 private immutable i_interval;
    uint256 private immutable i_baseFee;

    // Lottery data
    mapping(uint256 => LotteryRoom) private s_rooms;
    uint256[] private s_roomsIds;
    mapping(uint256 => uint256) private s_roomIndex;
    uint256 private s_lastId;

    event RoomCreated(uint256 indexed roomId, address indexed addr);
    event RoomEntered(uint256 indexed roomId, address indexed addr);
    event RoomLeft(uint256 indexed roomId, address indexed addr);
    event RoomWentToAwaiting(uint256 indexed roomId);
    event RoomDeleted(uint256 indexed roomId);

    constructor(
        uint256 subscriptionId,
        bytes32 gasLane,
        uint256 interval,
        uint256 baseFee,
        uint32 callbackGasLimit,
        address vrfCoordinatorV2
    ) VRFConsumerBaseV2Plus(vrfCoordinatorV2) {
        i_gasLane = gasLane;
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_baseFee = baseFee;
        i_callbackGasLimit = callbackGasLimit;
    }

    modifier checkBaseFee() {
        if (msg.value != i_baseFee) {
            revert LotteryAuction__IncorrectBaseFee();
        }
        _;
    }

    modifier checkRoomExists(uint256 roomId) {
        if (s_roomIndex[roomId] == 0) {
            revert LotteryAuction__RoomNotFound();
        }
        _;
    }

    function createRoom() external payable checkBaseFee {
        uint256 roomId = s_lastId;
        LotteryRoom storage room = s_rooms[roomId];

        room.state = LotteryState.AWAITING;
        room.playerToBet[msg.sender] = msg.value;
        room.lastTimestamp = block.timestamp;
        room.playersCount = 1;

        s_roomsIds.push(roomId);
        s_roomIndex[roomId] = s_roomsIds.length;
        s_lastId++;

        emit RoomCreated(roomId, msg.sender);
    }

    function enterRoom(uint256 roomId) external payable checkBaseFee checkRoomExists(roomId) {
        LotteryRoom storage room = s_rooms[roomId];

        if (room.playerToBet[msg.sender] != 0) {
            revert LotteryAuction__CantJoinTwice();
        }

        if (room.state == LotteryState.AUCTION || room.state == LotteryState.CALCULATING) {
            revert LotteryAuction__CantJoinNow();
        }

        room.playerToBet[msg.sender] = i_baseFee;

        uint32 playersCount = room.playersCount + 1;
        if (playersCount == 2) {
            room.state = LotteryState.OPEN;
            room.lastTimestamp = block.timestamp;
        }

        room.playersCount = playersCount;
        emit RoomEntered(roomId, msg.sender);
    }

    function leaveRoom(uint256 roomId) external checkRoomExists(roomId) {
        LotteryRoom storage room = s_rooms[roomId];

        if (room.playerToBet[msg.sender] == 0) {
            revert LotteryAuction__NotRoomMember();
        }

        LotteryState state = room.state;
        if (state == LotteryState.AUCTION || state == LotteryState.CALCULATING) {
            revert LotteryAuction__CantLeaveRoomNow();
        }

        delete room.playerToBet[msg.sender];
        emit RoomLeft(roomId, msg.sender);

        room.playersCount -= 1;
        if (room.playersCount == 1) {
            room.state = LotteryState.AWAITING;
            emit RoomWentToAwaiting(roomId);
        } else if (room.playersCount == 0) {
            uint256 indexToDelete = s_roomIndex[roomId] - 1;
            uint256 lastIndex = s_roomsIds.length - 1;
            uint256 lastRoomId = s_roomsIds[lastIndex];

            if (indexToDelete != lastIndex) {
                s_roomsIds[indexToDelete] = lastRoomId;
                s_roomIndex[lastRoomId] = indexToDelete + 1;
            }

            s_roomsIds.pop();
            delete s_roomIndex[roomId];
            delete s_rooms[roomId];

            emit RoomDeleted(roomId);
        }

        (bool success,) = msg.sender.call{value: i_baseFee}("");
        if (!success) {
            revert LotteryAuction__TransferFailed();
        }
    }
}
