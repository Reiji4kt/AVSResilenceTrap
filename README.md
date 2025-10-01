# README — AVSResilenceTrap

## Overview

**AVSResilenceTrap** is a Drosera-compatible proof-of-concept trap that monitors an EigenLayer AVS via an `IAVSDirectory` interface and flags (responds) when:

* the AVS directory is not set,
* the target AVS is not registered,
* the AVS has never published,
* the AVS's `lastPublished` is stale (older than a configurable block gap), or
* the recorded snapshot of the AVS's last published block differs from the current lastPublished (possible inconsistency across rounds).

This repo contains the trap contract `AVSResilienceTrap.sol`, a simple `AVSResponder.sol` response contract, and a `drosera.toml` sample configuration. ([GitHub][1])

---

## Files in this repo

* `src/AVSResilienceTrap.sol` — main Drosera trap (implements `ITrap`)
* `src/AVSResponder.sol` — simple response contract used by Drosera relay (emits alert event)
* `drosera.toml` — sample trap config you can adapt for Hoodi or other environments
* `README.md` — (this file) — documentation and test instructions. ([GitHub][1])

---

## Behaviour & data flow (brief)

1. **Operator** uses `setTargetAvs(address)` to pick the AVS to monitor (the trap was designed to rely on a single `targetAvs` stored on-chain to comply with `ITrap.collect()` signature which takes no args).
2. Drosera (or a human tester) calls `collect()` on the trap. `collect()` is `view` and gathers all deterministic on-chain checks (directory set, registered, lastPublished, snapshot mismatch) and returns a small encoded payload:
   `abi.encode(address avs, bool unhealthy, uint8 reasonCode)`
   where `reasonCode` values are:

   * `0` = OK
   * `1` = directory unset
   * `2` = not registered
   * `3` = never published
   * `4` = stale (missing heartbeat beyond `maxMissingBlocks`)
   * `5` = inconsistent (previous snapshot differs from current)
3. The relay calls `shouldRespond(bytes[] calldata data)` with `data[0] =` the `collect()` return. `shouldRespond` is `pure` and simply decodes the pre-collected payload and deterministically returns `(bool shouldRespond, bytes payload)` — when `shouldRespond` is true its payload is `abi.encode(address avs, uint8 reason)` which matches the response contract signature.
4. If the trap triggers, the Drosera relay calls the deployed response contract's `respondWithAVSFailure(address,uint8)` passing `(avs, reason)`.

---

## Deploying (quick)

1. `forge build` to compile.
2. Deploy `AVSResponder.sol` to your target network (e.g., Hoodi) — get its address.
3. Deploy `AVSResilienceTrap.sol` (no constructor args).
4. Call `setDirectory(<AVSDirectory address>)`, `setTargetAvs(<AVS address>)`, and optionally `snapshotPublish(<AVS>, <lastPubBlock>)` and `setMaxMissingBlocks(...)`.
5. Insert the `AVSResponder` address into `drosera.toml` as `response_contract` and set `response_function = "respondWithAVSFailure(address,uint8)"`. ([GitHub][1])

---

## Quick `cast` examples

> Replace `<RPC>`, `<TRAP_ADDRESS>`, and `<AVS>` with your values. For Hoodi use `https://ethereum-hoodi-rpc.publicnode.com`.

### 1) Call `collect()` (read-only) and decode output

```bash
# call collect() (returns hex)
COLLECT_RAW=$(cast call --rpc-url <RPC> <TRAP_ADDRESS> "collect()" )

# decode the return; the trap encodes (address avs, bool unhealthy, uint8 reason)
cast abi-decode "(address,bool,uint8)" "$COLLECT_RAW"
```

Example output:

```
(address) 0xAaA...
(bool) true
(uint8) 4
```

Interpretation: the trap considers the AVS unhealthy with reason code `4` (stale).

### 2) Simulate the relay calling `shouldRespond(bytes[])` — use Foundry script (recommended)

Directly crafting the `bytes[]` ABI for `shouldRespond` with `cast` is possible but error-prone. Instead it's simpler and more robust to run a small Foundry script (below) that:

* calls `collect()` (reads the trap),
* builds a `bytes[]` array containing that single bytes payload,
* calls `shouldRespond` with that array,
* decodes the returned `(bool, bytes)` to display the result.

(Foundry script provided below; if you still want a pure `cast`-only flow I include notes after the script.)

---

## Foundry script — `script/TestAVSResilienceTrap.s.sol`

Create file `script/TestAVSResilienceTrap.s.sol` and paste:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IAVSTrap {
    function collect() external view returns (bytes memory);
    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory);
}

contract TestAVSResilienceTrap is Script {
    function run() external {
        // -------------------------
        // USER CONFIGURE THESE
        // -------------------------
        string memory RPC = vm.envString("RPC_URL"); // e.g. "https://ethereum-hoodi-rpc.publicnode.com"
        address trap = vm.envAddress("TRAP_ADDRESS"); // deployed trap address
        // -------------------------

        vm.broadcast(); // not sending txs here — just enabling environment
        IAVSTrap t = IAVSTrap(trap);

        // 1) call collect()
        bytes memory collected = t.collect();
        console.log("collect() returned (raw bytes):", uint256(uint160(address(bytes20(keccak256(collected)))))); // quick fingerprint

        // decode collected: (address avs, bool unhealthy, uint8 reason)
        (address avs, bool unhealthy, uint8 reason) = abi.decode(collected, (address, bool, uint8));
        console.log("Collected avs:", toHexString(abi.encodePacked(avs)));
        console.log("Unhealthy:", unhealthy ? "true" : "false");
        console.log("Reason code:", uint256(reason));

        // 2) prepare bytes[] and call shouldRespond
        bytes;
        arr[0] = collected;

        (bool should, bytes memory payload) = t.shouldRespond(arr);
        console.log("shouldRespond ->", should ? "true" : "false");

        // payload is abi.encode(address avs, uint8 reason) per trap design when true
        (address pavs, uint8 preason) = abi.decode(payload, (address, uint8));
        console.log("Payload avs:", toHexString(abi.encodePacked(pavs)));
        console.log("Payload reason:", uint256(preason));
    }

    // helper to print bytes as hex
    function toHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < data.length; i++) {
            str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
}
```

How to run:

```bash
# set env vars (local)
export RPC_URL="https://ethereum-hoodi-rpc.publicnode.com"
export TRAP_ADDRESS="0xYourTrapAddressHere"

# run the script (this will use the local network you configured in foundry)
forge script script/TestAVSResilienceTrap.s.sol:TestAVSResilienceTrap --rpc-url $RPC_URL --broadcast
```

The script:

* calls `collect()` (view), decodes the collected tuple,
* packages it into a `bytes[]` and calls `shouldRespond` (pure),
* decodes and prints the returned payload.

This is the recommended way to test the trap’s logic end-to-end in a deterministic manner.

---

## Notes on pure `cast` for shouldRespond (advanced)

If you *must* use only `cast` to call `shouldRespond(bytes[])`, you need to ABI-encode the array-of-bytes properly. A rough sequence:

1. Get the raw `collect()` return (hex):

```bash
COLLECT_RAW=$(cast call --rpc-url <RPC> <TRAP_ADDRESS> "collect()")
```

2. Create the ABI for a `bytes[]` with one element equal to `COLLECT_RAW`. One approach is to use `cast abi-encode` to encode a `bytes` element, then wrap into an array by hand — this can be fiddly. Because of encoding subtleties, Foundry script is less error-prone and recommended.

---

## drosera.toml (example)

```toml
ethereum_rpc = "https://ethereum-hoodi-rpc.publicnode.com"
drosera_rpc = "https://relay.hoodi.drosera.io"
eth_chain_id = 560048
drosera_address = "0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D"

[traps]

[traps.avs_resilience]
path = "out/AVSResilienceTrap.sol/AVSResilienceTrap.json"
response_contract = "0xRESPONSE_CONTRACT_ADDRESS"   # replace with deployed AVSResponder
response_function = "respondWithAVSFailure(address,uint8)"
cooldown_period_blocks = 30
min_number_of_operators = 1
max_number_of_operators = 3
block_sample_size = 10
private_trap = true
whitelist = ["YOUR_OPERATOR_ADDRESS"]
```

---

## Attribution

Repository inspected: `Reiji4kt/AVSResilenceTrap`. ([GitHub][1])

---

