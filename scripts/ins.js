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

dotenv.config();

async function run() {
  const provider = new RpcProvider({
    nodeUrl:
      "https://starknet-goerli.infura.io/v3/2699b8fa15fe4a9fb74d186308ce5782",
  });
  const chainId = await provider.getChainId();

  const insContractAddress =
    "0x000aa1a2c83c25cb981a97e05b9a47bbf660b768eeab2f227677fd6e63614ee3";

  const { abi: insAbi } = await provider.getClassAt(insContractAddress);
  if (insAbi === undefined) {
    throw new Error("no abi.");
  }
  const insContract = new Contract(insAbi, insContractAddress, provider);

  const privateKey = process.env.PRIVATE_KEY;
  const accountAddress = process.env.ACCOUNT;

  const account = new Account(provider, accountAddress, privateKey, "1");

  const insData = [
    "0x7b202270223a20226272632d3230222c226f70223a20226465706c6f79222c",
    "0x227469636b223a20226f726469222c226d6178223a20223231303030303030",
    "0x222c226c696d223a202231303030227d",
  ];

  insContract.connect(account);

  const prefixSource = await insContract.get_prefix(1);
  const prefix = "0x" + prefixSource.toString(16);
  const nonce = await account.getNonce();
  const rawCalldata = insContract.populate(
    "ins",
    CallData.toCalldata([1, insData]) // 1 is bitwork_id
  );
  console.log("rawCalldata: ", rawCalldata);
  let tx_amount = 1;
  let calls = new Array(tx_amount).fill(rawCalldata);
  const rawCalldata2 = transaction.getExecuteCalldata(calls, "1");
  console.log("calldata: ", rawCalldata2);
  let maxFee = 6000000000000;
  let tx_hash = "";
  let transactionVersion = 1n;
  let cairoVersion = "1";
  let prefix_max = BigInt(prefix.padEnd(32, "f"));
  console.log("prefix_max", prefix_max.toString(16));
  let prefix_min = BigInt(prefix.padEnd(32, "0"));
  console.log("prefix_min", prefix_min.toString(16));

  while (true) {
    maxFee += 1;
    tx_hash = hash.calculateTransactionHash(
      accountAddress,
      transactionVersion,
      rawCalldata2,
      maxFee,
      chainId,
      nonce
    );

    let txHashFelt252 = num.hexToDecimalString(tx_hash);
    let txHashU252 = uint256.bnToUint256(txHashFelt252);
    let highFelt252 = num.hexToDecimalString(txHashU252.high);
    let high = BigInt(highFelt252);

    if (prefix_max >= high && high >= prefix_min) {
      console.log("get max fee: ", maxFee);
      console.log("get nonce: ", nonce);
      console.log("get tx_hash: ", tx_hash);
      break;
    }
  }

  const signerDetails = {
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
