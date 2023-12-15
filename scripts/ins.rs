use dotenvy::dotenv;
use starknet::{
    accounts::{
        Account, AccountError, Call, ConnectedAccount, Execution, ExecutionEncoding,
        SingleOwnerAccount,
    },
    core::{
        chain_id,
        crypto::compute_hash_on_elements,
        types::{BlockId, BlockTag, FieldElement, FunctionCall, InvokeTransactionResult},
        utils::get_selector_from_name,
    },
    signers::{LocalWallet, SigningKey},
};
use starknet_providers::{jsonrpc::HttpTransport, JsonRpcClient, Provider};
use std::{env, ops::Add};
use std::{
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Mutex,
    },
    time::Instant,
};
use structopt::StructOpt;
use tokio::{
    select,
    sync::{
        mpsc::{self},
        oneshot, Mutex as TokioMutex,
    },
    task::JoinHandle,
    time::interval,
};
use url::Url;

/// Cairo string for "invoke"
const PREFIX_INVOKE: FieldElement = FieldElement::from_mont([
    18443034532770911073,
    18446744073709551615,
    18446744073709551615,
    513398556346534256,
]);

#[derive(Debug, StructOpt)]
struct Opt {
    #[structopt(long, default_value = "3")]
    worker_count: usize,
}

#[tokio::main]
async fn main() {
    let opt = Opt::from_args();
    dotenv().expect(".env file not found");

    let provider = JsonRpcClient::new(HttpTransport::new(
        Url::parse("https://starknet-goerli.infura.io/v3/2699b8fa15fe4a9fb74d186308ce5782")
            .unwrap(),
    ));

    let signer = LocalWallet::from(SigningKey::from_secret_scalar(
        FieldElement::from_hex_be(&env::var("PRIVATE_KEY").unwrap()).unwrap(),
    ));

    let ins_contract_address = FieldElement::from_hex_be(
        "00aa1a2c83c25cb981a97e05b9a47bbf660b768eeab2f227677fd6e63614ee3",
    )
    .unwrap();
    let address = FieldElement::from_hex_be(&env::var("ACCOUNT").unwrap()).unwrap();
    print!("address: {:?}\n\n", address);

    let raw_calldata = Call {
        to: ins_contract_address,
        selector: get_selector_from_name("ins").unwrap(),
        calldata: vec![
            FieldElement::from_hex_be("1").unwrap(), // bitwork id
            FieldElement::from_hex_be("3").unwrap(),
            FieldElement::from_hex_be(
                "7b202270223a20226272632d3230222c226f70223a20226465706c6f79222c",
            )
            .unwrap(),
            FieldElement::from_hex_be(
                "227469636b223a20226f726469222c226d6178223a20223231303030303030",
            )
            .unwrap(),
            FieldElement::from_hex_be("222c226c696d223a202231303030227d").unwrap(),
        ],
    };

    let prefix_source = provider
        .call(
            FunctionCall {
                contract_address: ins_contract_address,
                entry_point_selector: get_selector_from_name("get_prefix").unwrap(),
                calldata: vec![FieldElement::from_hex_be("1").unwrap()],
            },
            BlockId::Tag(BlockTag::Latest),
        )
        .await
        .expect("failed to call contract");

    let (prefix_max, prefix_min) = if let Some(prefix_element) = prefix_source.get(0) {
        let prefix_hex = format!("{:x}", prefix_element);
        println!("prefix_hex: {:?}", prefix_hex);

        let min_hex = format!("{:0<1$}", prefix_hex, 62);
        let max_hex = format!("{:1$}", prefix_hex, 62).replace(" ", "f");

        let max = FieldElement::from_hex_be(&max_hex).unwrap();
        let min = FieldElement::from_hex_be(&min_hex).unwrap();

        println!("prefix_max: {:?}", max);
        println!("prefix_min: {:?}", min);
        (max, min)
    } else {
        println!("prefix_source is empty");
        (FieldElement::ZERO, FieldElement::ZERO)
    };

    let calls = vec![raw_calldata];
    let mut max_fee = 6000000000000_usize;
    let chain_id = chain_id::TESTNET;
    let account =
        SingleOwnerAccount::new(provider, signer, address, chain_id, ExecutionEncoding::New);
    let account = Arc::new(TokioMutex::new(account));
    let nonce = account.lock().await.get_nonce().await.unwrap();

    let encode_calls = custom_encode_calls(&calls);
    let call_hash = compute_hash_on_elements(&encode_calls);
    print!("encode_calls: {:?}\n\n", encode_calls);

    let hash_counter = Arc::new(AtomicUsize::new(0));
    let start = Instant::now();

    let stop_notify = Arc::new(tokio::sync::Notify::new());

    let (result_sender, mut result_receiver) = mpsc::channel::<FieldElement>(opt.worker_count); // Adjust buffer size as needed
    let mut worker_handles: Vec<JoinHandle<()>> = Vec::new();
    for i in 0..opt.worker_count {
        let max_fee_for_worker =
            FieldElement::from_dec_str(&(max_fee + 16 * 16 * 16 * 16 * i).to_string()).unwrap();
        println!("taskid: {}, max_fee_for_worker: {}", i, max_fee_for_worker);
        let counter = hash_counter.clone();
        let sender = result_sender.clone();
        let stop_notify_clone = stop_notify.clone();

        let handle = tokio::spawn(async move {
            let result = tokio::select! {
                result = tokio::task::spawn_blocking(move || {
                    // Call mine_worker and potentially check for stop_notify_clone periodically
                    mine_worker(
                        &call_hash,
                        max_fee_for_worker,
                        address,
                        chain_id,
                        &nonce.clone(),
                        prefix_max,
                        prefix_min,
                        counter,
                    ) // Assume this returns some result
                }) => result,
            };

            // Check the result of the computation
            match result {
                Ok(max_fee) => {
                    // Send the successful max_fee to the main loop
                    let _ = sender.send(max_fee).await;
                    // Notify other tasks to stop
                    stop_notify_clone.notify_waiters();
                }
                Err(e) => {
                    eprintln!("Computation failed: {:?}", e);
                    // You might still want to notify in case of failure
                    stop_notify_clone.notify_waiters();
                }
            };
        });
        worker_handles.push(handle);
    }

    let mut received = false;
    while !received {
        select! {
            max_fee = result_receiver.recv() => {
                if let Some(max_fee) = max_fee {
                    let account_clone = Arc::clone(&account);
                    let calls_clone = calls.clone();
                    tokio::spawn(async move {
                        let account_guard = account_clone.lock().await;
                        match invoke_ins(&*account_guard, calls_clone, &max_fee, &nonce).await {
                            Ok(tx_result) => {
                                println!("🙆 Successfully mined a ins: {:?}\n", tx_result.transaction_hash);
                            },
                            Err(e) => {
                                println!("⚠️ Failed to mine a ins: {:?}\n", e);
                            }
                        }
                    });
                    received = true; // Update the received flag
                }
            }
        }
    }
    // Notify all workers to stop, in case they aren't already
    stop_notify.notify_waiters();

    // Await the completion of all workers
    for handle in worker_handles {
        let _ = handle.await;
    }

    let duration = start.elapsed();
    println!("Time elapsed in expensive_function() is: {:?}", duration);
}

async fn invoke_ins(
    account: &SingleOwnerAccount<JsonRpcClient<HttpTransport>, LocalWallet>,
    calls: Vec<Call>,
    max_fee: &FieldElement,
    nonce: &FieldElement,
) -> Result<
    InvokeTransactionResult,
    AccountError<
        <SingleOwnerAccount<JsonRpcClient<HttpTransport>, LocalWallet> as Account>::SignError,
    >,
> {
    let prepared_execution = Execution::new(calls, account)
        .max_fee(*max_fee)
        .nonce(*nonce)
        .fee_estimate_multiplier(1.0)
        .prepared()
        .unwrap();
    let hash = &prepared_execution.transaction_hash(false);
    print!("sending hash: {:?}\n\n", hash);
    return prepared_execution.send().await;
}

fn mine_worker(
    &call_hash: &FieldElement,
    mut max_fee: FieldElement,
    address: FieldElement,
    chain_id: FieldElement,
    &nonce: &FieldElement,
    prefix_max: FieldElement,
    prefix_min: FieldElement,
    hash_counter: Arc<AtomicUsize>,
) -> FieldElement {
    loop {
        max_fee = max_fee.add(FieldElement::from_hex_be("1").unwrap());

        let hash: FieldElement = compute_hash_on_elements(&[
            PREFIX_INVOKE,
            FieldElement::ONE, // version
            address,
            FieldElement::ZERO, // entry_point_selector
            call_hash,
            max_fee,
            chain_id,
            nonce,
        ]);

        match prefix_max >= hash && hash >= prefix_min {
            true => {
                println!("get max fee: {}", max_fee);
                println!("get hash: {:x}", hash);
                print!("get counter: {}\n", hash_counter.load(Ordering::SeqCst));
                return max_fee;
            }
            false => {
                hash_counter.fetch_add(1, Ordering::SeqCst);
                continue;
            }
        };
    }
}

fn custom_encode_calls(calls: &[Call]) -> Vec<FieldElement> {
    let mut execute_calldata: Vec<FieldElement> = vec![calls.len().into()];
    for call in calls.iter() {
        execute_calldata.push(call.to); // to
        execute_calldata.push(call.selector); // selector

        execute_calldata.push(call.calldata.len().into()); // calldata.len()
        execute_calldata.extend_from_slice(&call.calldata);
    }
    execute_calldata
}
