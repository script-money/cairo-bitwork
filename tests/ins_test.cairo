use core::debug::PrintTrait;
use snforge_std::{
    declare, ContractClassTrait, start_prank, stop_prank, start_spoof, TxInfoMockTrait,
    cheatcodes::CheatTarget
};
use src::contracts::ins::{InsContractDispatcher, InsContractDispatcherTrait};
use starknet::{contract_address_const, ContractAddress};
use core::pedersen::{pedersen, PedersenTrait};
use core::array::SpanTrait;
use starknet::{contract_address_to_felt252, account::Call};
use core::hash::HashStateTrait;


#[test]
fn test_ins() {
    let ins_classhash = declare('Ins');
    let ins_args = array![
        0xffffffffffffffffffffffffffffffff
    ]; // this is max u128 value, can change difficuty to any value
    let ins_contract_address = ins_classhash.deploy(@ins_args).unwrap();
    let ins_dispatcher = InsContractDispatcher { contract_address: ins_contract_address };

    let ins_calldata = array![
        0x7b202270223a20226272632d3230222c226f70223a20226d696e74222c, // { "p": "brc-20","op": "mint",
        0x227469636b223a20226f726469222c226d6178223a20223231303030303030, // "tick": "ordi","max": "21000000
        0x222c226c696d6974223a202231303030227d, // ","limit": "1000"}
    ]; // the ins string data
    let raw_calldata = Call {
        to: ins_contract_address, selector: selector!("ins"), calldata: ins_calldata,
    };
    let calldata = get_execute_call_data(array![raw_calldata]);

    let mut tx_info = TxInfoMockTrait::default();
    let user = contract_address_const::<'USER'>();
    tx_info.account_contract_address = Option::Some(user);
    let max_fee =
        100000000000000; // user change max_fee from minumum to target to compute target tx hash
    tx_info.max_fee = Option::Some(max_fee);
    let message_hash = compute_transaction_hash(user, 1, @calldata, max_fee.into(), 'SN_GOERLI', 1);
    tx_info.transaction_hash = Option::Some(message_hash);
    start_spoof(CheatTarget::One(ins_contract_address), tx_info);
    ins_dispatcher.ins(calldata);
}

#[test]
#[should_panic(expected: ('tx hash is too big',))]
fn test_ins_fail() {
    let ins_classhash = declare('Ins');
    let ins_args = array![0xffffffffffffffffffff]; // need at least 8 zero
    let ins_contract_address = ins_classhash.deploy(@ins_args).unwrap();
    let ins_dispatcher = InsContractDispatcher { contract_address: ins_contract_address };

    let ins_calldata = array![
        0x7b202270223a20226272632d3230222c226f70223a20226465706c6f79222c,
        0x227469636b223a20226f726469222c226d6178223a20223231303030303030,
        0x222c226c696d223a202231303030227d,
    ];
    let raw_calldata = Call {
        to: ins_contract_address, selector: selector!("ins"), calldata: ins_calldata,
    };
    let calldata = get_execute_call_data(array![raw_calldata]);

    let mut tx_info = TxInfoMockTrait::default();
    let user = contract_address_const::<'USER'>();
    tx_info.account_contract_address = Option::Some(user);
    let max_fee = 100000000000000;
    tx_info.max_fee = Option::Some(max_fee);
    let message_hash = compute_transaction_hash(user, 1, @calldata, max_fee.into(), 'SN_GOERLI', 1);
    tx_info.transaction_hash = Option::Some(message_hash);
    start_spoof(CheatTarget::One(ins_contract_address), tx_info);
    ins_dispatcher.ins(calldata);
}


fn compute_hash_on_elements(elements: @Array<felt252>) -> felt252 {
    let mut state = PedersenTrait::new(0);
    let mut i = 0;
    loop {
        if i == elements.len() {
            break;
        }
        state = state.update(*elements.at(i));
        i += 1;
    };
    state.update(i.into()).finalize()
}

// helper functions, definition same as starknet.js
fn compute_transaction_hash(
    contractAddress: ContractAddress,
    version: felt252,
    calldata: @Array<felt252>,
    maxFee: felt252,
    chainId: felt252,
    nonce: felt252
) -> felt252 {
    let tx_hash = calculate_transaction_hash_common(
        'invoke', version, contractAddress, 0, calldata, maxFee, chainId, array![nonce]
    );
    tx_hash
}

fn get_execute_call_data(mut calls: Array<Call>) -> Array<felt252> {
    let mut result: Array<felt252> = ArrayTrait::new();
    result.append(calls.len().into());
    loop {
        match calls.pop_front() {
            Option::Some(mut call) => {
                result.append(contract_address_to_felt252(call.to));
                result.append(call.selector);
                result.append(call.calldata.len().into());
                let mut j = 0;
                loop {
                    if j == call.calldata.len() {
                        break;
                    }
                    result.append(*call.calldata.at(j));
                    j += 1;
                };
            },
            Option::None => { break; },
        };
    };
    result
}

fn calculate_transaction_hash_common(
    tx_hash_prefix: felt252,
    version: felt252,
    contract_address: ContractAddress,
    entry_point_selector: felt252,
    calldata: @Array<felt252>,
    max_fee: felt252,
    chain_id: felt252,
    additional_data: Array<felt252>
) -> felt252 {
    let calldata_hash = compute_hash_on_elements(calldata);
    let mut dataToHash = array![
        tx_hash_prefix,
        version,
        contract_address_to_felt252(contract_address),
        entry_point_selector,
        calldata_hash,
        max_fee,
        chain_id
    ];
    let mut i = 0;
    loop {
        if i == additional_data.len() {
            break;
        }
        dataToHash.append(*additional_data.at(i));
        i += 1;
    };
    let tx_hash = compute_hash_on_elements(@dataToHash);
    tx_hash
}
