use starknet::{
    accounts::{Call, ConnectedAccount, Execution, ExecutionEncoding, SingleOwnerAccount},
    core::{
        chain_id,
        crypto::compute_hash_on_elements,
        types::{BlockId, BlockTag, FieldElement, FunctionCall},
        utils::get_selector_from_name,
    },
    signers::{LocalWallet, SigningKey},
};
use starknet_providers::{jsonrpc::HttpTransport, JsonRpcClient, Provider};

use dotenvy::dotenv;
use std::time::Instant;
use std::{env, ops::Add};
use url::Url;

#[tokio::main]
async fn main() {
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

    /// Cairo string for "invoke"
    const PREFIX_INVOKE: FieldElement = FieldElement::from_mont([
        18443034532770911073,
        18446744073709551615,
        18446744073709551615,
        513398556346534256,
    ]);

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

        println!("prefix_max: {:?}", max); // 0x00aaffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        println!("prefix_min: {:?}", min); // 0x00aa000000000000000000000000000000000000000000000000000000000000
        (max, min)
    } else {
        println!("prefix_source is empty");
        (FieldElement::ZERO, FieldElement::ZERO)
    };

    let calls = vec![raw_calldata];
    let mut max_fee = FieldElement::from_hex_be("574fbde6000").unwrap(); // 6000000000000
    let chain_id = chain_id::TESTNET;
    let account =
        SingleOwnerAccount::new(provider, signer, address, chain_id, ExecutionEncoding::New);

    let nonce = account.get_nonce().await.unwrap();
    let encode_calls = custom_encode_calls(&calls);
    let call_hash = compute_hash_on_elements(&encode_calls);
    print!("encode_calls: {:?}\n\n", encode_calls);
    let mut count = 0;
    let start = Instant::now();

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
        // print!("hash: {:?}\n\n", hash);

        match prefix_max >= hash && hash >= prefix_min {
            true => {
                println!("get max fee: {}", max_fee);
                println!("get nonce: {}", nonce);
                print!("count: {:?}\n\n", count);
                break;
            }
            false => {
                count += 1;
            }
        }
    }
    let duration = start.elapsed();
    println!("Time elapsed in expensive_function() is: {:?}", duration);

    let prepared_execution = Execution::new(calls, &account)
        .max_fee(max_fee)
        .nonce(nonce)
        .fee_estimate_multiplier(1.0)
        .prepared()
        .unwrap();
    let hash = &prepared_execution.transaction_hash(false);
    print!("hash: {:?}\n\n", hash);
    let tx = prepared_execution.send().await.unwrap();
    dbg!(&tx.transaction_hash);
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
