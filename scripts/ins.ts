import {
  Account,
  Contract,
  RpcProvider,
  hash,
  CallData,
  transaction,
  num,
  uint256,
} from "starknet";
import dotenv from "dotenv";
import { Call } from "starknet";
import { InvocationsSignerDetails } from "starknet";
import { CairoVersion } from "starknet";

dotenv.config();

async function run(): Promise<void> {
  const provider = new RpcProvider({
    nodeUrl:
      "https://starknet-goerli.infura.io/v3/2699b8fa15fe4a9fb74d186308ce5782",
  });
  const chainId = await provider.getChainId();

  const insContractAddress: string =
    "0x000aa1a2c83c25cb981a97e05b9a47bbf660b768eeab2f227677fd6e63614ee3";

  const { abi: insAbi } = await provider.getClassAt(insContractAddress);
  if (insAbi === undefined) {
    throw new Error("no abi.");
  }
  const insContract = new Contract(insAbi, insContractAddress, provider);

  const privateKey: string | undefined = process.env.PRIVATE_KEY;
  const accountAddress: string | undefined = process.env.ACCOUNT;

  if (privateKey === undefined || accountAddress === undefined) {
    throw new Error("no private key or account in .env");
  }

  const account = new Account(provider, accountAddress!, privateKey!, "1");

  const insData: string[] = [
    "0x7b202270223a20226272632d3230222c226f70223a20226465706c6f79222c",
    "0x227469636b223a20226f726469222c226d6178223a20223231303030303030",
    "0x222c226c696d223a202231303030227d",
  ];

  insContract.connect(account);

  const prefixSource: number = await insContract.get_prefix(1);
  const prefix: string = "0x" + prefixSource.toString(16);
  const nonce: string = await account.getNonce();
  const rawCalldata = insContract.populate(
    "ins",
    CallData.toCalldata([1, insData]) // 1 is bitwork_id
  );
  console.log("rawCalldata: ", rawCalldata);
  let tx_amount: number = 1;
  let calls: Call[] = new Array(tx_amount).fill(rawCalldata);
  const rawCalldata2 = transaction.getExecuteCalldata(calls, "1");
  console.log("calldata: ", rawCalldata2);
  let maxFee: number = 6000000000000;
  let tx_hash: string = "";
  let transactionVersion: bigint = 1n;
  let cairoVersion: CairoVersion = "1";
  let prefix_max: bigint = BigInt(prefix.padEnd(32, "f"));
  console.log("prefix_max", prefix_max.toString(16));
  let prefix_min: bigint = BigInt(prefix.padEnd(32, "0"));
  console.log("prefix_min", prefix_min.toString(16));

  while (true) {
    maxFee += 1;
    tx_hash = hash.calculateTransactionHash(
      accountAddress!,
      transactionVersion,
      rawCalldata2,
      maxFee,
      chainId,
      nonce
    );

    let txHashFelt252: string = num.hexToDecimalString(tx_hash);
    let txHashU252: any = uint256.bnToUint256(txHashFelt252);
    let highFelt252: string = num.hexToDecimalString(txHashU252.high);
    let high: bigint = BigInt(highFelt252);

    if (prefix_max >= high && high >= prefix_min) {
      console.log("get max fee: ", maxFee);
      console.log("get nonce: ", nonce);
      console.log("get tx_hash: ", tx_hash);
      break;
    }
  }

  const signerDetails: InvocationsSignerDetails = {
    walletAddress: accountAddress,
    nonce,
    maxFee,
    version: transactionVersion,
    chainId,
    cairoVersion,
  };
  const signature = await account.signer.signTransaction(calls, signerDetails);
  console.log("signature: ", signature);
  const res = await account.invokeFunction(
    {
      contractAddress: accountAddress,
      calldata: rawCalldata2,
      signature,
    },
    {
      nonce,
      maxFee,
      version: transactionVersion,
    }
  );

  console.log(res);
}

run().catch((err) => console.error(err));
