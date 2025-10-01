// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

interface IAVSDirectory {
    function isAVS(address avs) external view returns (bool);
    function lastPublished(address avs) external view returns (uint256); // assumed block number
}

contract AVSResilienceTrap is ITrap {
    address public owner;
    IAVSDirectory public avsDirectory;
    uint256 public maxMissingBlocks; // allowed block gap since lastPublished
    mapping(address => uint256) public lastSeenPublishBlock;

    // Cached AVS for the last collect() run
    address public targetAvs;

    constructor() {
        owner = msg.sender;
        maxMissingBlocks = 12; // default ~heartbeat tolerance
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    function setDirectory(address _d) external onlyOwner {
        avsDirectory = IAVSDirectory(_d);
    }

    function setMaxMissingBlocks(uint256 _blocks) external onlyOwner {
        maxMissingBlocks = _blocks;
    }

    function snapshotPublish(address avs, uint256 lastPublishedBlock) external onlyOwner {
        lastSeenPublishBlock[avs] = lastPublishedBlock;
    }

    function setTargetAvs(address _avs) external onlyOwner {
        targetAvs = _avs;
    }

    // ------------------------------------------------------------------------
    // ITrap implementation
    // ------------------------------------------------------------------------

    /// @notice Collects data about the target AVS.
    /// Encodes (avs, unhealthy, reasonCode)
    /// reasonCode: 0=ok, 1=dirUnset, 2=notRegistered, 3=neverPublished, 4=stale, 5=inconsistent
    function collect() external view override returns (bytes memory) {
        address avs = targetAvs;
        bool unhealthy = false;
        uint8 reason = 0;

        if (address(avsDirectory) == address(0)) {
            unhealthy = true;
            reason = 1;
        } else if (!avsDirectory.isAVS(avs)) {
            unhealthy = true;
            reason = 2;
        } else {
            uint256 lastPubBlock = avsDirectory.lastPublished(avs);

            if (lastPubBlock == 0) {
                unhealthy = true;
                reason = 3;
            } else if (block.number > lastPubBlock + maxMissingBlocks) {
                unhealthy = true;
                reason = 4;
            }

            uint256 prev = lastSeenPublishBlock[avs];
            if (prev != 0 && prev != lastPubBlock) {
                unhealthy = true;
                reason = 5;
            }
        }

        return abi.encode(avs, unhealthy, reason);
    }

    /// @notice Pure check on pre-collected data
    function shouldRespond(bytes[] calldata data) external pure override returns (bool, bytes memory) {
        require(data.length > 0, "missing data");
        (address avs, bool unhealthy, uint8 reason) = abi.decode(data[0], (address, bool, uint8));

        if (unhealthy) {
            return (true, abi.encode(avs, reason));
        }
        return (false, abi.encode(avs, reason));
    }
}
