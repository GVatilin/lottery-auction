// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

contract LotteryRoom {
    error LotteryRoom__IncorrectBaseFee();
    error LotteryRoom__CantLeaveRoomNow();
    error LotteryRoom__RoomNotFound();
    error LotteryRoom__TransferFailed();
    error LotteryRoom__NotRoomMember();
    error LotteryRoom__CantJoinTwice();
    error LotteryRoom__CantJoinNow();

    enum LotteryState {
        AWAITING,
        OPEN,
        AUCTION,
        CALCULATING,
        CALCULATING_AUCTION
    }

    struct Room {
        LotteryState state;
        mapping(address player => uint256 bet) playerToBet;
        address payable[] playersAddr;
        mapping(address player => uint256 indexPlusOne) playerIndex;
        uint256 lastTimestamp;
        uint256 playersCount;
        uint256 interval;
        uint256 betsAmount;
    }

    // Settings
    uint256 private immutable i_baseFee;

    // Rooms data
    mapping(uint256 roomId => Room room) internal s_rooms;
    uint256[] internal s_roomsIds;
    mapping(uint256 roomId => uint256 roomIndex) internal s_roomIndex;
    uint256 private s_lastId;

    event RoomCreated(uint256 indexed roomId, address indexed addr);
    event RoomEntered(uint256 indexed roomId, address indexed addr);
    event RoomLeft(uint256 indexed roomId, address indexed addr);
    event RoomWentToAwaiting(uint256 indexed roomId);
    event RoomDeleted(uint256 indexed roomId);

    constructor(uint256 baseFee) {
        i_baseFee = baseFee;
    }

    modifier checkBaseFee() {
        if (msg.value != i_baseFee) {
            revert LotteryRoom__IncorrectBaseFee();
        }
        _;
    }

    modifier checkRoomExists(uint256 roomId) {
        if (s_roomIndex[roomId] == 0) {
            revert LotteryRoom__RoomNotFound();
        }
        _;
    }

    function createRoom(uint256 interval) external payable checkBaseFee {
        uint256 roomId = s_lastId;
        Room storage room = s_rooms[roomId];

        room.state = LotteryState.AWAITING;
        room.lastTimestamp = block.timestamp;
        room.playersCount = 1;
        room.interval = interval;
        room.betsAmount += i_baseFee;

        _addPlayer(room, msg.sender, msg.value);

        s_roomsIds.push(roomId);
        s_roomIndex[roomId] = s_roomsIds.length;
        s_lastId++;

        emit RoomCreated(roomId, msg.sender);
    }

    function enterRoom(uint256 roomId) external payable checkBaseFee checkRoomExists(roomId) {
        Room storage room = s_rooms[roomId];

        if (room.playerToBet[msg.sender] != 0) {
            revert LotteryRoom__CantJoinTwice();
        }

        if (room.state != LotteryState.OPEN && room.state != LotteryState.AWAITING) {
            revert LotteryRoom__CantJoinNow();
        }

        _addPlayer(room, msg.sender, msg.value);

        uint256 playersCount = room.playersCount + 1;
        if (playersCount == 2) {
            room.state = LotteryState.OPEN;
            room.lastTimestamp = block.timestamp;
        }

        room.playersCount = playersCount;
        room.betsAmount += i_baseFee;

        emit RoomEntered(roomId, msg.sender);
    }

    function leaveRoom(uint256 roomId) external checkRoomExists(roomId) {
        Room storage room = s_rooms[roomId];

        if (room.playerToBet[msg.sender] == 0) {
            revert LotteryRoom__NotRoomMember();
        }

        LotteryState state = room.state;
        if (state != LotteryState.OPEN && state != LotteryState.AWAITING) {
            revert LotteryRoom__CantLeaveRoomNow();
        }

        uint256 refund = room.playerToBet[msg.sender];
        delete room.playerToBet[msg.sender];
        _removePlayer(room, msg.sender);
        room.betsAmount -= refund;

        emit RoomLeft(roomId, msg.sender);

        room.playersCount = uint32(room.playersAddr.length);
        if (room.playersCount == 1) {
            room.state = LotteryState.AWAITING;
            emit RoomWentToAwaiting(roomId);
        } else if (room.playersCount == 0) {
            _deleteRoom(roomId);
            emit RoomDeleted(roomId);
        }

        (bool success,) = msg.sender.call{value: refund}("");
        if (!success) {
            revert LotteryRoom__TransferFailed();
        }
    }

    function _deleteRoom(uint256 roomId) internal {
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
    }

    function _addPlayer(Room storage room, address player, uint256 value) private {
        room.playerToBet[player] = value;
        room.playersAddr.push(payable(player));
        room.playerIndex[player] = room.playersAddr.length;
    }

    function _removePlayer(Room storage room, address player) private {
        uint256 indexToDelete = room.playerIndex[player] - 1;
        uint256 lastIndex = room.playersAddr.length - 1;

        if (indexToDelete != lastIndex) {
            address payable lastPlayer = room.playersAddr[lastIndex];
            room.playersAddr[indexToDelete] = lastPlayer;
            room.playerIndex[lastPlayer] = indexToDelete + 1;
        }

        room.playersAddr.pop();
        delete room.playerIndex[player];
    }
}
