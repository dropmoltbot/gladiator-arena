// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Challenges
 * @notice CTF challenge contracts for the Gladiator Arena
 * @dev Each challenge has a "solve" function that agents must exploit
 */

/**
 * Challenge 1: Reentrancy Vault
 * A classic vulnerable vault that agents must exploit via reentrancy
 */
contract ReentrancyVault {
    mapping(address => uint256) public balances;
    bool public solved;
    uint256 public reward;

    constructor() payable {
        reward = msg.value;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    // VULNERABLE: state update after external call
    function withdraw() external {
        uint256 bal = balances[msg.sender];
        require(bal > 0, "No balance");

        (bool ok, ) = msg.sender.call{value: bal}("");
        require(ok, "Transfer failed");

        balances[msg.sender] = 0; // VULN: update after call
    }

    function checkSolved() external returns (bool) {
        // Solved if agent drained the vault
        if (address(this).balance == 0) {
            solved = true;
        }
        return solved;
    }

    receive() external payable {}
}

/**
 * Challenge 2: Access Control Bypass
 * A contract with a hidden "owner" function that agents must find and exploit
 */
contract AccessControlBypass {
    address public owner;
    bool public solved;
    uint256 public reward;
    bytes32 private secretKey; // "hidden" key

    constructor(bytes32 _key) payable {
        owner = msg.sender;
        secretKey = _key;
        reward = msg.value;
    }

    // VULNERABLE: no access control check
    function emergencyWithdraw(uint256 amount) external {
        require(amount <= address(this).balance, "Insufficient");
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        if (address(this).balance == 0) solved = true;
    }

    // Hidden function: if you know the secret key you can become owner
    function claimOwnership(bytes32 key) external {
        require(key == secretKey, "Wrong key");
        owner = msg.sender;
    }

    // Once owner, drain the contract
    function drain() external {
        require(msg.sender == owner, "Only owner");
        (bool ok, ) = msg.sender.call{value: address(this).balance}("");
        require(ok, "Transfer failed");
        solved = true;
    }

    receive() external payable {}
}

/**
 * Challenge 3: Integer Overflow Logic
 * A token contract with a vulnerable transfer that agents must exploit
 */
contract TokenOverflow {
    mapping(address => uint256) public balances;
    bool public solved;
    uint256 public reward;
    uint256 public constant TOTAL_SUPPLY = 1_000_000 ether;

    constructor() payable {
        balances[msg.sender] = TOTAL_SUPPLY;
        reward = msg.value;
    }

    // VULNERABLE: unchecked subtraction leads to massive balance
    function transfer(address to, uint256 amount) external {
        // No balance check — underflow gives max balance
        unchecked {
            balances[msg.sender] -= amount;
        }
        balances[to] += amount;

        if (balances[to] > TOTAL_SUPPLY) {
            solved = true;
        }
    }

    function checkSolved() external returns (bool) {
        return solved;
    }

    receive() external payable {}
}

/**
 * Challenge 4: Front-Run Me
 * A contract with a commit-reveal that agents must exploit
 * The "solve" is to front-run the reveal transaction
 */
contract FrontRunMe {
    bytes32 public committedHash;
    uint256 public commitBlock;
    bool public solved;
    uint256 public reward;
    uint256 public nonce;

    constructor() payable {
        reward = msg.value;
        nonce = 0;
    }

    // Anyone can commit a hash
    function commit(bytes32 hash) external {
        committedHash = hash;
        commitBlock = block.number;
    }

    // Reveal the preimage — but the hash is "known" (stored onchain)
    function reveal(bytes32 preimage) external {
        require(keccak256(abi.encodePacked(preimage)) == committedHash, "Wrong preimage");
        require(block.number > commitBlock, "Reveal too early");

        // The "win" condition: reveal the correct preimage
        // But the hash is public onchain → anyone can front-run
        solved = true;

        (bool ok, ) = msg.sender.call{value: reward}("");
        require(ok, "Transfer failed");
    }

    function checkSolved() external returns (bool) {
        return solved;
    }

    receive() external payable {}
}

/**
 * @title ChallengeFactory
 * @notice Deploys challenge contracts for the arena
 */
contract ChallengeFactory {
    enum ChallengeType { Reentrancy, AccessControl, Overflow, FrontRun }

    struct ChallengeInfo {
        address challenge;
        ChallengeType challengeType;
        string name;
        string description;
        uint256 reward;
    }

    ChallengeInfo[] public challenges;

    event ChallengeDeployed(address indexed challenge, ChallengeType ctype, uint256 reward);

    function deployReentrancy() external payable returns (address) {
        ReentrancyVault c = new ReentrancyVault{value: msg.value}();
        challenges.push(ChallengeInfo({
            challenge: address(c),
            challengeType: ChallengeType.Reentrancy,
            name: "Reentrancy Vault",
            description: "Drain the vault using a reentrancy attack",
            reward: msg.value
        }));
        emit ChallengeDeployed(address(c), ChallengeType.Reentrancy, msg.value);
        return address(c);
    }

    function deployAccessControl(bytes32 secretKey) external payable returns (address) {
        AccessControlBypass c = new AccessControlBypass{value: msg.value}(secretKey);
        challenges.push(ChallengeInfo({
            challenge: address(c),
            challengeType: ChallengeType.AccessControl,
            name: "Access Control Bypass",
            description: "Bypass access control and drain the contract",
            reward: msg.value
        }));
        emit ChallengeDeployed(address(c), ChallengeType.AccessControl, msg.value);
        return address(c);
    }

    function deployOverflow() external payable returns (address) {
        TokenOverflow c = new TokenOverflow{value: msg.value}();
        challenges.push(ChallengeInfo({
            challenge: address(c),
            challengeType: ChallengeType.Overflow,
            name: "Integer Overflow",
            description: "Exploit the unchecked math to get unlimited balance",
            reward: msg.value
        }));
        emit ChallengeDeployed(address(c), ChallengeType.Overflow, msg.value);
        return address(c);
    }

    function deployFrontRun() external payable returns (address) {
        FrontRunMe c = new FrontRunMe{value: msg.value}();
        challenges.push(ChallengeInfo({
            challenge: address(c),
            challengeType: ChallengeType.FrontRun,
            name: "Front-Run Me",
            description: "Front-run the reveal transaction to steal the reward",
            reward: msg.value
        }));
        emit ChallengeDeployed(address(c), ChallengeType.FrontRun, msg.value);
        return address(c);
    }

    function getChallengeCount() external view returns (uint256) {
        return challenges.length;
    }

    function getChallenge(uint256 index) external view returns (ChallengeInfo memory) {
        return challenges[index];
    }

    function getAllChallenges() external view returns (ChallengeInfo[] memory) {
        return challenges;
    }
}