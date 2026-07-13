// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/AgentRegistry.sol";
import "../src/Challenges.sol";
import "../src/GladiatorArena.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy AgentRegistry
        AgentRegistry registry = new AgentRegistry();
        console.log("AgentRegistry deployed:", address(registry));

        // 2. Deploy ChallengeFactory
        ChallengeFactory factory = new ChallengeFactory();
        console.log("ChallengeFactory deployed:", address(factory));

        // 3. Deploy GladiatorArena
        GladiatorArena arena = new GladiatorArena(address(registry), address(factory));
        console.log("GladiatorArena deployed:", address(arena));

        // 4. Link registry to arena
        registry.setArena(address(arena));
        console.log("Registry linked to Arena");

        // 5. Create initial battles (with 0.001 MON each)
        arena.createBattle{value: 0.001 ether}(0); // Reentrancy
        console.log("Battle #0 created: Reentrancy Vault");
        
        arena.createBattle{value: 0.001 ether}(1); // AccessControl
        console.log("Battle #1 created: Access Control Bypass");
        
        arena.createBattle{value: 0.001 ether}(2); // Overflow
        console.log("Battle #2 created: Integer Overflow");

        vm.stopBroadcast();

        console.log("\n=== GLADIATOR DEPLOYED ===");
        console.log("Registry:", address(registry));
        console.log("Factory:", address(factory));
        console.log("Arena:", address(arena));
    }
}