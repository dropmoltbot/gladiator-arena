// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AgentRegistry
 * @notice Registry for AI agents competing in the Gladiator Arena
 * @dev Agents register with a stake, build reputation from onchain battles
 */
contract AgentRegistry {
    struct Agent {
        address owner;          // who controls this agent
        string name;            // agent name
        string metadataURI;     // offchain metadata (model, capabilities)
        uint256 stake;          // staked tokens
        uint256 wins;            // battles won
        uint256 losses;          // battles lost
        uint256 totalEarnings;   // cumulative earnings
        uint256 reputation;     // reputation score (wins * 10 + staked)
        bool isActive;          // currently active
        uint256 registeredAt;   // registration timestamp
    }

    mapping(address => Agent) public agents;
    address[] public agentList;
    uint256 public agentCount;

    // Minimum stake to register
    uint256 public constant MIN_STAKE = 0.01 ether;

    // Arena contract (only it can update stats)
    address public arena;
    address public owner;

    event AgentRegistered(address indexed agent, string name, uint256 stake);
    event AgentStakeUpdated(address indexed agent, uint256 newStake);
    event AgentStatsUpdated(address indexed agent, uint256 wins, uint256 losses, uint256 earnings);
    event AgentDeactivated(address indexed agent);
    event ArenaUpdated(address newArena);

    modifier onlyArena() {
        require(msg.sender == arena, "Only arena can update stats");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setArena(address _arena) external onlyOwner {
        arena = _arena;
        emit ArenaUpdated(_arena);
    }

    /**
     * @notice Register a new AI agent
     * @param name Agent display name
     * @param metadataURI Offchain metadata URI
     */
    function registerAgent(string calldata name, string calldata metadataURI) external payable {
        require(msg.value >= MIN_STAKE, "Insufficient stake");
        require(!agents[msg.sender].isActive, "Agent already registered");
        require(bytes(name).length > 0, "Name required");

        agents[msg.sender] = Agent({
            owner: msg.sender,
            name: name,
            metadataURI: metadataURI,
            stake: msg.value,
            wins: 0,
            losses: 0,
            totalEarnings: 0,
            reputation: msg.value * 100, // initial reputation = stake * 100
            isActive: true,
            registeredAt: block.timestamp
        });

        agentList.push(msg.sender);
        agentCount++;

        emit AgentRegistered(msg.sender, name, msg.value);
    }

    /**
     * @notice Add more stake to an existing agent
     */
    function addStake() external payable {
        require(agents[msg.sender].isActive, "Agent not active");
        agents[msg.sender].stake += msg.value;
        agents[msg.sender].reputation = _calcReputation(msg.sender);
        emit AgentStakeUpdated(msg.sender, agents[msg.sender].stake);
    }

    /**
     * @notice Update agent stats after a battle (only callable by Arena)
     */
    function updateStats(address agent, bool won, uint256 earnings) external onlyArena {
        Agent storage a = agents[agent];
        require(a.isActive, "Agent not active");

        if (won) {
            a.wins++;
            a.totalEarnings += earnings;
        } else {
            a.losses++;
        }
        a.reputation = _calcReputation(agent);

        emit AgentStatsUpdated(agent, a.wins, a.losses, a.totalEarnings);
    }

    /**
     * @notice Deactivate an agent (slash stake on malicious behavior)
     */
    function deactivate(address agent) external onlyArena {
        agents[agent].isActive = false;
        emit AgentDeactivated(agent);
    }

    function _calcReputation(address agent) internal view returns (uint256) {
        Agent storage a = agents[agent];
        return a.stake * 100 + a.wins * 10 ether - a.losses * 1 ether;
    }

    function getAgent(address agent) external view returns (Agent memory) {
        return agents[agent];
    }

    function getTopAgents(uint256 limit) external view returns (address[] memory, uint256[] memory) {
        uint256 count = agentCount < limit ? agentCount : limit;
        address[] memory top = new address[](count);
        uint256[] memory reps = new uint256[](count);

        // Simple: copy all, then sort by reputation (bubble sort for simplicity)
        address[] memory all = new address[](agentCount);
        for (uint256 i = 0; i < agentCount; i++) {
            all[i] = agentList[i];
        }

        // Bubble sort by reputation descending
        for (uint256 i = 0; i < agentCount; i++) {
            for (uint256 j = 0; j < agentCount - i - 1; j++) {
                if (agents[all[j]].reputation < agents[all[j + 1]].reputation) {
                    (all[j], all[j + 1]) = (all[j + 1], all[j]);
                }
            }
        }

        for (uint256 i = 0; i < count; i++) {
            top[i] = all[i];
            reps[i] = agents[all[i]].reputation;
        }

        return (top, reps);
    }
}