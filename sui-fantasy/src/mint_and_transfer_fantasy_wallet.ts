import {
  Connection,
  Ed25519Keypair,
  JsonRpcProvider,
  RawSigner,
  TransactionBlock,
} from "@mysten/sui.js";
import * as dotenv from "dotenv";

dotenv.config({ path: "../.env" });

const phrase = process.env.ADMIN_PHRASE;
const fullnode = process.env.FULLNODE!;
const keypair = Ed25519Keypair.deriveKeypair(phrase!);
const adminAddress = keypair.getPublicKey().toSuiAddress();
const provider = new JsonRpcProvider(
  new Connection({
    fullnode: fullnode,
  })
);
const signer = new RawSigner(keypair, provider);
const moduleName = "fantasy_wallet";
const packageId = process.env.PACKAGE_ID;
const registryId = process.env.REGISTRY_ID!;

let transactionBlock = new TransactionBlock();

transactionBlock.moveCall({
  target: `${packageId}::${moduleName}::mint_and_transfer_fantasy_wallet`,
  arguments: [transactionBlock.object(registryId)],
});

transactionBlock.setGasBudget(10000000);
signer
  .signAndExecuteTransactionBlock({
    transactionBlock,
    requestType: "WaitForLocalExecution",
    options: {
      showObjectChanges: true,
      showEffects: true,
    },
  })
  .then((result) => {
    console.log(result);
  });
