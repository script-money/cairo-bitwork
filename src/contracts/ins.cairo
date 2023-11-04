#[starknet::interface]
trait InsContract<TContractState> {
    fn ins(ref self: TContractState, bitwork_id: usize, ins: Array<felt252>);
    fn get_prefix(self: @TContractState, bitwork_id: usize) -> u128;
}

#[starknet::contract]
mod Ins {
    use core::traits::Into;
    use core::integer::u256_from_felt252;
    use alexandria_math::{BitShift, count_digits_of_base};

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Ins: Ins,
    }

    #[derive(Drop, starknet::Event)]
    struct Ins {
        inscribe: felt252,
        ins: Array<felt252>,
    }

    #[storage]
    struct Storage {
        used_sigs: LegacyMap<felt252, bool>,
        bitwork_id: LegacyMap<usize, u128>,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.bitwork_id.write(1, 0xaa);
    }

    #[external(v0)]
    impl InsImpl of super::InsContract<ContractState> {
        fn ins(ref self: ContractState, bitwork_id: usize, ins: Array<felt252>) {
            let tx_info = starknet::get_tx_info().unbox();

            let tx_hash = tx_info.transaction_hash;
            let high = u256_from_felt252(tx_hash).high;

            let prefix = self.bitwork_id.read(bitwork_id);
            let size = count_digits_of_base(prefix, 16);
            let head_letter = BitShift::shr(high, count_digits_of_base(high, 16) * 4 - size * 4);

            assert(head_letter == prefix, 'tx hash is not for this bitwork');
            assert(!self.used_sigs.read(tx_hash), 'tx hash is already used');
            let inscribe = 'inscribe';
            // TODO: verify ins data is correct
            self.emit(Event::Ins(Ins { inscribe, ins }));
            self.used_sigs.write(tx_hash, true);
        }

        fn get_prefix(self: @ContractState, bitwork_id: usize) -> u128 {
            self.bitwork_id.read(bitwork_id)
        }
    }
}
