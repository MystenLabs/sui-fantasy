// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module sui_fantasy::fantasy_wallet_tests {
    use std::string;

    use sui::tx_context::{TxContext, dummy};

    use sui_fantasy::fantasy_wallet;

    use oracle::decimal_value;

    #[test]
    fun test_swap() {
        let fantasy_wallet = fantasy_wallet::mint_for_testing(&mut ctx());

        fantasy_wallet::swap_for_testing(
            &mut fantasy_wallet,
            string::utf8(b"sui"),
            string::utf8(b"eth"),
            1_000
        );

        assert!(decimal_value::value(&fantasy_wallet::sui(&fantasy_wallet)) == 999_000, 0);
        assert!(decimal_value::value(&fantasy_wallet::eth(&fantasy_wallet)) == 1_000_500, 0);

        fantasy_wallet::burn_for_testing(fantasy_wallet);
    }

    #[test]
    #[expected_failure(abort_code = sui_fantasy::fantasy_wallet::EInsufficientAmount)]
    fun test_swap_insufficient_amount(){
        let fantasy_wallet = fantasy_wallet::mint_for_testing(&mut ctx());

        fantasy_wallet::swap_for_testing(
            &mut fantasy_wallet,
            string::utf8(b"sui"),
            string::utf8(b"eth"),
            1_000_001
        );

        assert!(decimal_value::value(&fantasy_wallet::sui(&fantasy_wallet)) == 995_000, 0);
        assert!(decimal_value::value(&fantasy_wallet::eth(&fantasy_wallet)) == 5_000_000_000, 0);

        fantasy_wallet::burn_for_testing(fantasy_wallet);
    }

    fun ctx(): TxContext { dummy() }
}
