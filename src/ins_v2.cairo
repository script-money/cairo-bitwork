use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait InsContract<TContractState> {
    fn ins(ref self: TContractState, bitwork_id: usize, ins: Array<felt252>);
    fn get_prefix(self: @TContractState, bitwork_id: usize) -> u128;
    fn deploy(ref self: TContractState, bit: u128);
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}


#[starknet::contract]
mod Ins_v2 {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::access::ownable::interface::IOwnable;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::{ContractAddress, ClassHash};

    use core::traits::Into;
    use core::integer::u256_from_felt252;
    use alexandria_math::{BitShift, count_digits_of_base};
    use starknet::syscalls::replace_class_syscall;
    use starknet::get_caller_address;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    /// Ownable
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;

    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    /// Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Ins: Ins,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event
    }


    #[derive(Drop, starknet::Event)]
    struct Ins {
        inscribe: felt252,
        ins: Array<felt252>,
    }

    #[storage]
    struct Storage {
        used_sigs: LegacyMap<felt252, bool>,
        bitwork: LegacyMap<usize, u128>,
        index: usize,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage
    }

    #[constructor]
    fn constructor(ref self: ContractState, bit: u128) {
        let owner = get_caller_address();
        self.ownable.initializer(owner);
        let i = 1_usize;
        self.index.write(i);
        self.bitwork.write(i, bit);
    }

    #[external(v0)]
    impl InsImpl of super::InsContract<ContractState> {
        fn ins(ref self: ContractState, bitwork_id: usize, ins: Array<felt252>) {
            let tx_info = starknet::get_tx_info().unbox();

            let tx_hash = tx_info.transaction_hash;
            let high = u256_from_felt252(tx_hash).high;

            let prefix = self.bitwork.read(bitwork_id);
            let size = count_digits_of_base(prefix, 16);
            let head_letter = BitShift::shr(high, count_digits_of_base(high, 16) * 4 - size * 4);

            assert(head_letter == prefix, 'tx hash is not for this bitwork');
            assert(!self.used_sigs.read(tx_hash), 'tx hash is already used');
            let inscribe = 'inscribe2';

            self.emit(Event::Ins(Ins { inscribe, ins }));
            self.used_sigs.write(tx_hash, true);
        }

        fn get_prefix(self: @ContractState, bitwork_id: usize) -> u128 {
            self.bitwork.read(bitwork_id)
        }

        fn deploy(ref self: ContractState, bit: u128) {
            let latest_index = self.index.read();
            let new_index = latest_index + 1;
            self.index.write(new_index);
            self.bitwork.write(new_index, bit);
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.ownable.owner()
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable._upgrade(new_class_hash);
        }
    }
}
