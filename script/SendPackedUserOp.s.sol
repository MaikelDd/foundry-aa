// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MinimalAccount} from "src/MinimalAccount.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;
    address constant RANDOM_APPROVER =
        0xBDEB869a058A729bD91E0c82257d61F81294aEa2;

    function run() public {
        HelperConfig helperConfig = new HelperConfig();
        address dest = helperConfig.getConfig().usdc;
        uint256 value = 0;
        address minimalAccountAddress = DevOpsTools.get_most_recent_deployment(
            "MinimalAccount",
            block.chainid
        );

        // First encode the approve call
        bytes memory approveData = abi.encodeWithSelector(
            IERC20.approve.selector,
            RANDOM_APPROVER,
            1e18
        );

        // Then encode the execute call with the approve data
        bytes memory executeData = abi.encodeWithSelector(
            MinimalAccount.execute.selector,
            dest,
            value,
            approveData
        );

        PackedUserOperation memory userOp = generateSignedUserOperation(
            executeData,
            helperConfig.getConfig(),
            minimalAccountAddress
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        // send transaction
        vm.startBroadcast();
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(
            ops,
            payable(helperConfig.getConfig().account)
        );
        vm.stopBroadcast();
    }

    /**
     * @notice Generate a signed user operation
     * @param callData The data to be executed
     * @param config The network configuration
     * @param minimalAccount The minimal account address
     * @return The signed user operation
     */
    function generateSignedUserOperation(
        bytes memory callData,
        HelperConfig.NetworkConfig memory config,
        address minimalAccount
    ) public view returns (PackedUserOperation memory) {
        // 1. generate the unsigned data
        uint256 nonce = vm.getNonce(minimalAccount) - 1;
        PackedUserOperation memory userOp = _generateUnsignedUserOperation(
            callData,
            minimalAccount,
            nonce
        );
        // 2. get the userOpHash
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(
            userOp
        );
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        // 3. Sign it with the burner wallet's private key
        uint8 v;
        bytes32 r;
        bytes32 s;
        if (block.chainid == 31337) {
            // For local testing, use the default anvil key
            uint256 ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
            (v, r, s) = vm.sign(ANVIL_DEFAULT_KEY, digest);
        } else {
            // For Sepolia, use the burner wallet's private key
            // The burner wallet is the owner of the MinimalAccount
            (v, r, s) = vm.sign(vm.envUint("PRIVATE_KEY"), digest);
        }
        userOp.signature = abi.encodePacked(r, s, v);
        return userOp;
    }

    function _generateUnsignedUserOperation(
        bytes memory callData,
        address sender,
        uint256 nonce
    ) internal pure returns (PackedUserOperation memory) {
        // Increase gas limits to more reasonable values for Sepolia
        uint128 verificationGasLimit = 200000; // Increased for Sepolia
        uint128 callGasLimit = 200000; // Increased for Sepolia
        uint128 maxPriorityFeePerGas = 2 gwei; // Increased for Sepolia
        uint128 maxFeePerGas = 50 gwei; // Increased for Sepolia

        // Pack gas limits and fees correctly
        bytes32 accountGasLimits = bytes32(
            (uint256(verificationGasLimit) << 128) | uint256(callGasLimit)
        );
        bytes32 gasFees = bytes32(
            (uint256(maxPriorityFeePerGas) << 128) | uint256(maxFeePerGas)
        );

        return
            PackedUserOperation({
                sender: sender,
                nonce: nonce,
                initCode: hex"",
                callData: callData,
                accountGasLimits: accountGasLimits,
                preVerificationGas: 50000, // Fixed value for Sepolia
                gasFees: gasFees,
                paymasterAndData: hex"",
                signature: hex""
            });
    }
}
