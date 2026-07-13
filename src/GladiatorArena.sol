// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AgentRegistry.sol";
import "./Challenges.sol";

/**
 * @title GladiatorArena
 * @notice Onchain Agent Combat Arena — AI agents battle to solve CTF challenges
 * @dev First valid solution wins the pot. Spectators bet on winners.
 * 
 * MONAD ANGLE: Multiple battles run in parallel (independent state).
 * Agents submit solutions simultaneously — OCC resolves who was first.
 */
contract GladiatorArena {
    struct Battle {
        uint256 battleId;
        address challenge;         // CTF challenge contract
        string challengeName;
        uint256 reward;            // reward for the winner
        uint256 deadline;          // battle deadline
        address[] participants;    // registered agents
        mapping(address => bool) hasParticipated;
        address winner;            // first to solve
        bytes winnerSolution;      // winning solution calldata
        bool resolved;
        uint256 createdAt;
        uint256 solvedAt;
        uint256 solveTime;         // time to solve (seconds)
    }

    struct BattleInfo {
        uint256 battleId;
        address challenge;
        string challengeName;
        uint256 reward;
        uint256 deadline;
        uint256 participantCount;
        address winner;
        bool resolved;
        uint256 createdAt;
        uint256 solveTime;
    }

    AgentRegistry public registry;
    ChallengeFactory public factory;

    mapping(uint256 => Battle) public battles;
    uint256 public battleCount;

    // Betting: battleId => bettor => amount (0 = no bet)
    // Bet on agent: battleId => agent => totalBetAmount
    mapping(uint256 => mapping(address => uint256)) public agentBets; // total bet on agent
    mapping(uint256 => mapping(address => mapping(address => uint256))) publicbettorBets; // bettor => agent => amount
    mapping(uint256 => address[]) public battleBettors;

    address public owner;
    uint256 public constant MIN_BATTLE_REWARD = 0.001 ether;
    uint256 public constant BATTLE_DURATION = 1 hours;

    event BattleCreated(uint256 indexed battleId, address challenge, string name, uint256 reward, uint256 deadline);
    event AgentJoinedBattle(uint256 indexed battleId, address indexed agent);
    event SolutionSubmitted(uint256 indexed battleId, address indexed agent, bool success, uint256 gasUsed);
    event BattleResolved(uint256 indexed battleId, address winner, uint256 solveTime, uint256 reward);
    event BetPlaced(uint256 indexed battleId, address indexed bettor, address indexed agent, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(address _registry, address _factory) {
        registry = AgentRegistry(_registry);
        factory = ChallengeFactory(_factory);
        owner = msg.sender;
    }

    /**
     * @notice Create a new battle with a CTF challenge
     * @param challengeType 0=Reentrancy, 1=AccessControl, 2=Overflow, 3=FrontRun
     */
    function createBattle(uint8 challengeType) external payable returns (uint256) {
        require(msg.value >= MIN_BATTLE_REWARD, "Insufficient reward");

        address challenge;
        string memory name;
        bytes32 secretKey = keccak256(abi.encodePacked(block.timestamp, msg.sender, block.number));

        if (challengeType == 0) {
            challenge = factory.deployReentrancy{value: msg.value}();
            name = "Reentrancy Vault";
        } else if (challengeType == 1) {
            challenge = factory.deployAccessControl{value: msg.value}(secretKey);
            name = "Access Control Bypass";
        } else if (challengeType == 2) {
            challenge = factory.deployOverflow{value: msg.value}();
            name = "Integer Overflow";
        } else if (challengeType == 3) {
            challenge = factory.deployFrontRun{value: msg.value}();
            name = "Front-Run Me";
        } else {
            revert("Invalid challenge type");
        }

        uint256 battleId = battleCount++;
        Battle storage b = battles[battleId];
        b.battleId = battleId;
        b.challenge = challenge;
        b.challengeName = name;
        b.reward = msg.value;
        b.deadline = block.timestamp + BATTLE_DURATION;
        b.createdAt = block.timestamp;

        emit BattleCreated(battleId, challenge, name, msg.value, b.deadline);
        return battleId;
    }

    /**
     * @notice An agent joins a battle
     */
    function joinBattle(uint256 battleId) external {
        (, , , , , , , , bool isActive, ) = registry.agents(msg.sender);
        require(isActive, "Agent not registered");
        Battle storage b = battles[battleId];
        require(block.timestamp < b.deadline, "Battle ended");
        require(!b.hasParticipated[msg.sender], "Already joined");

        b.participants.push(msg.sender);
        b.hasParticipated[msg.sender] = true;

        emit AgentJoinedBattle(battleId, msg.sender);
    }

    /**
     * @notice Submit a solution — the agent's attack transaction
     * @param battleId The battle to solve
     * @param target The challenge contract to call
     * @param data The calldata (exploit payload)
     */
    function submitSolution(uint256 battleId, address target, bytes calldata data) external {
        Battle storage b = battles[battleId];
        require(b.hasParticipated[msg.sender], "Not joined");
        require(block.timestamp < b.deadline, "Battle ended");
        require(!b.resolved, "Already solved");

        // Check that the agent is registered
        (, , , , , , , , bool active, ) = registry.agents(msg.sender);
        require(active, "Agent not registered");

        // Execute the agent's attack transaction
        uint256 gasBefore = gasleft();
        (bool success, ) = target.call(data);
        uint256 gasUsed = gasBefore - gasleft();

        // Check if the challenge was solved
        bool solved = _checkSolved(b.challenge);

        emit SolutionSubmitted(battleId, msg.sender, solved, gasUsed);

        if (solved) {
            b.winner = msg.sender;
            b.winnerSolution = data;
            b.resolved = true;
            b.solvedAt = block.timestamp;
            b.solveTime = block.timestamp - b.createdAt;

            // Transfer reward to winner
            (bool ok, ) = msg.sender.call{value: b.reward}("");
            require(ok, "Reward transfer failed");

            // Update agent stats
            registry.updateStats(msg.sender, true, b.reward);

            // Distribute betting pool
            _distributeBets(battleId, msg.sender);

            emit BattleResolved(battleId, msg.sender, b.solveTime, b.reward);
        } else {
            // Failed attempt — update losses
            registry.updateStats(msg.sender, false, 0);
        }
    }

    /**
     * @notice Place a bet on which agent will win a battle
     * @param battleId The battle
     * @param agent The agent you bet on
     */
    function placeBet(uint256 battleId, address agent) external payable {
        Battle storage b = battles[battleId];
        require(block.timestamp < b.deadline, "Battle ended");
        require(!b.resolved, "Already resolved");
        (, , , , , , , , bool agentActive, ) = registry.agents(agent);
        require(agentActive, "Agent not registered");
        require(msg.value > 0, "No bet");

        if (publicbettorBets[battleId][msg.sender][agent] == 0) {
            battleBettors[battleId].push(msg.sender);
        }

        publicbettorBets[battleId][msg.sender][agent] += msg.value;
        agentBets[battleId][agent] += msg.value;

        emit BetPlaced(battleId, msg.sender, agent, msg.value);
    }

    function _distributeBets(uint256 battleId, address winner) internal {
        Battle storage b = battles[battleId];
        uint256 totalPool = _getTotalBets(battleId);

        if (totalPool == 0) return;

        // Distribute to bettors who bet on the winner
        uint256 winnerPool = agentBets[battleId][winner];
        if (winnerPool == 0) return;

        address[] memory bettors = battleBettors[battleId];
        for (uint256 i = 0; i < bettors.length; i++) {
            address bettor = bettors[i];
            uint256 betOnWinner = publicbettorBets[battleId][bettor][winner];
            if (betOnWinner > 0) {
                // Proportional share of total pool
                uint256 share = (betOnWinner * totalPool) / winnerPool;
                (bool ok, ) = bettor.call{value: share}("");
                require(ok, "Bet payout failed");
            }
        }
    }

    function _getTotalBets(uint256 battleId) internal view returns (uint256) {
        address[] memory bettors = battleBettors[battleId];
        uint256 total = 0;
        for (uint256 i = 0; i < bettors.length; i++) {
            // Sum all bets from this bettor
            // We need to check all agents they bet on
            // For simplicity, we track via the battle bettor list
            // In production, iterate through participants
        }
        return total; // Simplified — real impl tracks total
    }

    function _checkSolved(address challenge) internal returns (bool) {
        // Try calling checkSolved() on the challenge
        (bool ok, bytes memory data) = challenge.call(abi.encodeWithSignature("checkSolved()"));
        if (ok && data.length >= 32) {
            return abi.decode(data, (bool));
        }
        // Fallback: check if challenge balance is 0
        return challenge.balance == 0;
    }

    function getBattleInfo(uint256 battleId) external view returns (BattleInfo memory) {
        Battle storage b = battles[battleId];
        return BattleInfo({
            battleId: b.battleId,
            challenge: b.challenge,
            challengeName: b.challengeName,
            reward: b.reward,
            deadline: b.deadline,
            participantCount: b.participants.length,
            winner: b.winner,
            resolved: b.resolved,
            createdAt: b.createdAt,
            solveTime: b.solveTime
        });
    }

    function getParticipants(uint256 battleId) external view returns (address[] memory) {
        return battles[battleId].participants;
    }

    function getActiveBattles() external view returns (uint256[] memory) {
        uint256[] memory active = new uint256[](battleCount);
        uint256 count = 0;
        for (uint256 i = 0; i < battleCount; i++) {
            if (!battles[i].resolved && block.timestamp < battles[i].deadline) {
                active[count++] = i;
            }
        }
        // Trim array
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = active[i];
        }
        return result;
    }
}