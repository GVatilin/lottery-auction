// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {LotteryRoom} from "./LotteryRoom.sol";

contract LotteryAuction is VRFConsumerBaseV2Plus, AutomationCompatibleInterface, LotteryRoom {
    error LotteryAuction__TransferFailed();
    error LotteryAuction__UpkeepNotNeeded();
    error LotteryAuction__AuctionUnavailable();
    error LotteryAuction__ZeroBalance();
    error LotteryAuction__AuctionIsClosed();
    error LotteryAuction__CantBetZero();

    // Chainlink Settings
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_gasLimit;

    // Lottery data
    mapping(uint256 requestId => uint256 roomId) private s_requestToRoom;
    mapping(address player => uint256 balance) private s_playerToBalance;

    event LotteryAuctionEnded(uint256 indexed roomId);
    event AuctionFunded(uint256 indexed roomId, address indexed addr);
    event WinningsWithdrawn(address indexed player, uint256 amount);

    constructor(
        uint256 subscriptionId,
        bytes32 gasLane,
        uint256 baseFee,
        uint32 gasLimit,
        address vrfCoordinatorV2,
        uint256 maxPlayers
    ) VRFConsumerBaseV2Plus(vrfCoordinatorV2) LotteryRoom(baseFee, maxPlayers) {
        i_subscriptionId = subscriptionId;
        i_gasLane = gasLane;
        i_gasLimit = gasLimit;
    }

    function checkUpkeep(
        bytes memory /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        for (uint256 i = 0; i < s_roomsIds.length; ++i) {
            uint256 roomId = s_roomsIds[i];
            Room storage room = s_rooms[roomId];
            if (_isUpkeepNeeded(room)) {
                return (true, abi.encode(roomId));
            }
        }
        return (false, bytes(""));
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 roomId = abi.decode(performData, (uint256));

        if (s_roomIndex[roomId] == 0) {
            revert LotteryRoom__RoomNotFound(roomId);
        }

        Room storage room = s_rooms[roomId];

        if (!_isUpkeepNeeded(room)) {
            revert LotteryAuction__UpkeepNotNeeded();
        }

        if (room.state == LotteryState.OPEN) {
            room.state = LotteryState.CALCULATING;
        } else {
            room.state = LotteryState.CALCULATING_AUCTION;
        }

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_gasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );

        s_requestToRoom[requestId] = roomId;
    }

    function fundAuction(uint256 roomId) external payable checkRoomExists(roomId) {
        Room storage room = s_rooms[roomId];

        if (room.playerToBet[msg.sender] == 0) {
            revert LotteryRoom__NotRoomMember();
        }

        if (room.state != LotteryState.AUCTION) {
            revert LotteryAuction__AuctionUnavailable();
        }

        if (_isTimePassed(room)) {
            revert LotteryAuction__AuctionIsClosed();
        }

        if (msg.value == 0) {
            revert LotteryAuction__CantBetZero();
        }

        room.playerToBet[msg.sender] += msg.value;
        room.betsAmount += msg.value;

        emit AuctionFunded(roomId, msg.sender);
    }

    function withdraw() external {
        uint256 balance = s_playerToBalance[msg.sender];
        if (balance == 0) {
            revert LotteryAuction__ZeroBalance();
        }

        delete s_playerToBalance[msg.sender];

        (bool success,) = msg.sender.call{value: balance}("");
        if (!success) {
            revert LotteryAuction__TransferFailed();
        }

        emit WinningsWithdrawn(msg.sender, balance);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        uint256 roomId = s_requestToRoom[requestId];
        delete s_requestToRoom[requestId];
        Room storage room = s_rooms[roomId];

        if (room.state == LotteryState.CALCULATING) {
            _selectAuctionPlayers(room, randomWords[0]);
            room.lastTimestamp = block.timestamp;
            room.state = LotteryState.AUCTION;
        } else if (room.state == LotteryState.CALCULATING_AUCTION) {
            address payable winner = _selectWinner(room, randomWords[0]);
            uint256 prize = room.betsAmount;

            _deleteRoom(roomId);
            emit LotteryAuctionEnded(roomId);

            s_playerToBalance[winner] += prize;
        }
    }

    function _isUpkeepNeeded(Room storage room) private view returns (bool) {
        LotteryState state = room.state;
        bool isOpen = (state == LotteryState.OPEN) || (state == LotteryState.AUCTION);
        bool timePassed = _isTimePassed(room);

        return isOpen && timePassed;
    }

    function _selectAuctionPlayers(Room storage room, uint256 randomWord) private {
        uint256 playersLength = room.playersAddr.length;
        uint256 survivorsCount = playersLength / 2;

        address payable[] memory shuffledPlayers = room.playersAddr;

        for (uint256 i; i < survivorsCount; ++i) {
            uint256 randomIndex = i + (uint256(keccak256(abi.encode(randomWord, i))) % (playersLength - i));
            (shuffledPlayers[i], shuffledPlayers[randomIndex]) = (shuffledPlayers[randomIndex], shuffledPlayers[i]);
        }

        for (uint256 i = survivorsCount; i < playersLength; ++i) {
            delete room.playerToBet[shuffledPlayers[i]];
            delete room.playerIndex[shuffledPlayers[i]];
        }

        delete room.playersAddr;

        for (uint256 i; i < survivorsCount; ++i) {
            address payable survivor = shuffledPlayers[i];
            room.playersAddr.push(survivor);
            room.playerIndex[survivor] = i + 1;
        }

        room.playersCount = survivorsCount;
    }

    function _selectWinner(Room storage room, uint256 randomWord) private view returns (address payable) {
        uint256 playersSum = 0;
        for (uint256 i = 0; i < room.playersAddr.length; ++i) {
            address playerAddr = room.playersAddr[i];
            playersSum += room.playerToBet[playerAddr];
        }

        uint256 winnerNum = randomWord % playersSum;
        uint256 curSum = 0;
        address payable winner;

        for (uint256 i = 0; i < room.playersAddr.length; ++i) {
            address payable player = room.playersAddr[i];
            curSum += room.playerToBet[player];

            if (winnerNum < curSum) {
                winner = player;
                break;
            }
        }

        return winner;
    }

    function _isTimePassed(Room storage room) private view returns (bool) {
        return block.timestamp >= room.interval + room.lastTimestamp;
    }

    function getBalance() external view returns (uint256) {
        return s_playerToBalance[msg.sender];
    }
}
