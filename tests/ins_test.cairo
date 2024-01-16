use core::clone::Clone;
use core::debug::PrintTrait;
use snforge_std::{
    declare, ContractClassTrait, start_prank, stop_prank, start_spoof, TxInfoMockTrait,
    cheatcodes::CheatTarget, test_address, get_class_hash
};
use src::ins::{InsContractDispatcher, InsContractDispatcherTrait};
use starknet::{contract_address_const, ContractAddress};
use core::pedersen::{pedersen, PedersenTrait};
use core::array::SpanTrait;
use starknet::{contract_address_to_felt252, account::Call};
use core::hash::HashStateTrait;
use alexandria_math::{BitShift, count_digits_of_base};
use core::integer;
use cairo_transaction::transaction::get_execute_call_data;
use cairo_transaction::hash::calculate_transaction_hash;

fn deploy_ins() -> ContractAddress {
    let ins_classhash = declare('Ins');
    let ins_args = array![0x1234_u128.into()];
    let ins_contract_address = ins_classhash.deploy(@ins_args).unwrap();
    ins_contract_address
}

#[test]
fn test_owner() {
    let contract_address = deploy_ins();
    let owner_dispatcher = InsContractDispatcher { contract_address: contract_address };

    let owner = owner_dispatcher.get_owner();
    assert(owner == test_address(), 'owner not equal');
}

#[test]
fn test_upgrade() {
    let contract_address = deploy_ins();
    let upgrade_dispatcher = InsContractDispatcher { contract_address: contract_address };
    let old_class_hash = get_class_hash(upgrade_dispatcher.contract_address);
    let Ins_v2_classhash = declare('Ins_v2');
    upgrade_dispatcher.upgrade(Ins_v2_classhash.class_hash);
    let new_class_hash = get_class_hash(upgrade_dispatcher.contract_address);
    assert(old_class_hash != new_class_hash, 'class hash is equal');
    let owner = upgrade_dispatcher.get_owner();
    assert(owner == test_address(), 'owner not equal');
}

#[test]
#[should_panic(expected: ('tx hash is not for this bitwork',))]
fn test_ins_fail() {
    let ins_contract_address = deploy_ins();
    let ins_dispatcher = InsContractDispatcher { contract_address: ins_contract_address };

    let prefix = ins_dispatcher.get_prefix(1);
    assert(prefix == 0x1234, 'prefix not equal');
    let ins_calldata = array![
        1,
        3,
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
    let message_hash = calculate_transaction_hash(
        user, 1, @calldata, max_fee.into(), 'SN_GOERLI', 1
    );
    tx_info.transaction_hash = Option::Some(message_hash);
    start_spoof(CheatTarget::One(ins_contract_address), tx_info);
    ins_dispatcher.ins(1, calldata);
}
#[test]
fn test_ins() {
    let ins_contract_address = deploy_ins();
    let ins_dispatcher = InsContractDispatcher { contract_address: ins_contract_address };

    let ins_calldata = array![
        1,
        3,
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
    // let message_hash = compute_transaction_hash(user, 1, @calldata, max_fee.into(), 'SN_GOERLI', 1);
    tx_info
        .transaction_hash =
            Option::Some(
                0x123486fce2644ae69c017a0ead8d85c4c98c0abbbb426dcfbfeaaa9995f55c
            ); // tx hash should start with 0x1234
    start_spoof(CheatTarget::One(ins_contract_address), tx_info);
    ins_dispatcher.ins(1, calldata);
}

#[test]
fn bitshift_test() {
    let high_number = 0x9fea3b4ae39d546a08b3bc97cc9cf6b4;
    let low_number = 0x4936e2c361f6961d8fac94fdd396e6bb;
    let prefix = 4;
    let suffix = 4;
    let shift_amount = count_digits_of_base(high_number, 16) * 4 - prefix * 4;
    let head_letter = BitShift::shr(high_number, shift_amount);
    assert(head_letter == 0x9fea, 'first 4 digits not equal');

    let mask = BitShift::shl(1, suffix * 4) - 1; // 0xffff
    let (bit_and, _, _) = integer::bitwise(low_number, mask);
    assert(bit_and == 0xe6bb, 'last 4 digits not equal');
}

#[test]
fn prefix_test() {
    let prefix = 0x9fea;
    let size = count_digits_of_base(prefix, 16);
    assert(size == 4, 'prefix size not equal');
    let high_number = 0x9fea3b4ae39d546a08b3bc97cc9cf6b4;
    let shift_amount = count_digits_of_base(high_number, 16) * 4 - size * 4;
    let head_letter = BitShift::shr(high_number, shift_amount);
    assert(head_letter == prefix, 'first 4 digits not equal');
}
