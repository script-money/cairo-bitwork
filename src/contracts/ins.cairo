#[starknet::interface]
trait InsContract<TContractState> {
    fn ins(ref self: TContractState, ins: Array<felt252>);
}

#[starknet::contract]
mod Ins {
    use core::debug::PrintTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use core::traits::Into;
    use core::integer::u256_from_felt252;

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
        difficulty: u128,
    }

    #[constructor]
    fn constructor(ref self: ContractState, difficulty: u128) {
        self.difficulty.write(difficulty);
    }

    #[external(v0)]
    impl InsImpl of super::InsContract<ContractState> {
        fn ins(ref self: ContractState, ins: Array<felt252>) {
            let tx_info = starknet::get_tx_info().unbox();
            // let mut tx_info_array = array![];
            // tx_info.serialize(ref tx_info_array);
            // 'tx_info_array'.print();
            // tx_info_array.print();
            let tx_hash = tx_info.transaction_hash;
            assert(!self.used_sigs.read(tx_hash), 'tx hash is already used');
            assert(u256_from_felt252(tx_hash).high < self.difficulty.read(), 'tx hash is too big');
            let inscribe = 'inscribe';
            self.emit(Event::Ins(Ins { inscribe, ins }));
            self.used_sigs.write(tx_hash, true);
        }
    }
}
