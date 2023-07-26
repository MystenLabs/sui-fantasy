// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// This module defines the fantasy wallet for the sui-fantasy game.
module sui_fantasy::fantasy_wallet {
    use std::option::{Self, Option};
    use std::string::{Self, String, utf8};

    use sui::dynamic_field as dfield;
    use sui::math;
    use sui::object::{Self, UID};
    use sui::package;
    use sui::transfer::{Self};
    use sui::tx_context::{Self, TxContext};

    // Importing necessary modules from the oracle package.
    use oracle::data::{Self, Data};
    use oracle::decimal_value::{Self, DecimalValue};
    use oracle::simple_oracle::{Self, SimpleOracle};

    /// Error code for when someone tries to claim an NFT again.
    const EAlreadyRegistered: u64 = 0;

    /// Error code for when someone tries to swap bigger amount that owns.
    const EInsufficientAmount: u64 = 1;

    /// Error code for when someone tries to swap between two currencies that are not supported.
    const EUnsupportedExchange: u64 = 2;

    // ======== Types =========

    /// Struct defining the FantasyWallet with different types of currencies.
    struct FantasyWallet has key {
        id: UID,
        btc: DecimalValue,
        dai: DecimalValue,
        eth: DecimalValue,
        eur: DecimalValue,
        sui: DecimalValue,
        usd: DecimalValue,
        usdc: DecimalValue,
        wbtc: DecimalValue,
    }

    /// Struct defining the Registry.
    struct Registry has key { id: UID }

    /// Struct defining the AdminCap which belongs to the creator of the game.
    struct AdminCap has key, store { id: UID }

    /// One Time Witness to create the `Publisher`.
    struct FANTASY_WALLET has drop {}

    // ======== Functions =========

    /// Module initializer. Uses One Time Witness to create Publisher and transfer it to sender.
    fun init(otw: FANTASY_WALLET, ctx: &mut TxContext) {
        package::claim_and_keep(otw, ctx);
        let cap = AdminCap { id: object::new(ctx) };
        transfer::public_transfer(cap, tx_context::sender(ctx));
        transfer::share_object(Registry { id: object::new(ctx) });
    }


    // ======= Mint/Register Functions =======

    /// Get a "FantasyWallet". Can only be called once.
    /// Aborts when trying to be called again.
    public fun get_fantasy_wallet(
        registry: &mut Registry, 
        ctx: &mut TxContext
    ): FantasyWallet {
        let sender = tx_context::sender(ctx);

        assert!(
            !dfield::exists_with_type<address, bool>(&registry.id, sender), 
            EAlreadyRegistered
        );

        dfield::add<address, bool>(&mut registry.id, sender, true);
        mint(ctx)
    }

    /// Function to mint and transfer a "FantasyWallet" to the sender.
    public fun mint_and_transfer_fantasy_wallet(
        registry: &mut Registry, 
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        // Asserts that the sender is not already registered.
        assert!(
            !dfield::exists_with_type<address, bool>(&registry.id, sender), 
            EAlreadyRegistered
        );

        // Adds the sender to the registry.
        dfield::add<address, bool>(&mut registry.id, sender, true);
        mint_and_transfer(ctx);
    }

    fun mint(
        ctx: &mut TxContext
    ): FantasyWallet {
        FantasyWallet {
            id: object::new(ctx),
            btc: decimal_value::new(1_000_000, 4),
            dai: decimal_value::new(1_000_000, 4),
            eth: decimal_value::new(1_000_000, 4),
            eur: decimal_value::new(1_000_000, 4),
            sui: decimal_value::new(1_000_000, 4),
            usd: decimal_value::new(1_000_000, 4),
            usdc: decimal_value::new(1_000_000, 4),
            wbtc: decimal_value::new(1_000_000, 4),
        }
    }

    /// Function to mint and transfer a new fantasy wallet to the sender.
    fun mint_and_transfer(
        ctx: &mut TxContext
    ) {
        transfer::transfer(
            mint(ctx),
            tx_context::sender(ctx)
        );
    }

    // ======= Fantasy Wallet Functions =======

    /// Function to swap between two currencies in a fantasy wallet using an oracle.
    public fun swap(
        fantasy_wallet: &mut FantasyWallet,
        oracle: &SimpleOracle,
        coinA: String,
        coinB: String,
        amount: u64
    ) {
        let coinA_decimal_value = get_coin_decimal_value(fantasy_wallet, coinA);
        let coinB_decimal_value = get_coin_decimal_value(fantasy_wallet, coinB);

        // Asserts that the value of coinA is greater than or equal to the amount being swapped.
        assert!(decimal_value::value(&coinA_decimal_value) >= amount, EInsufficientAmount);

        // Gets the latest data from the oracle for the exchange rate between coinA and coinB.
        let single_data = simple_oracle_get_latest_data(oracle, coinA, coinB);
        let single_data = option::destroy_some(single_data);
        let single_data_value = data::value(&single_data);
        let rate_decimals = decimal_value::decimal(single_data_value);
        let rate_value = decimal_value::value(single_data_value);

        let rate: DecimalValue;

        if (decimal_value::decimal(&coinA_decimal_value) > rate_decimals) {
            rate = decimal_value::new(
                rate_value * (math::pow(10, decimal_value::decimal(&coinA_decimal_value) - rate_decimals) as u64),
                rate_decimals + (decimal_value::decimal(&coinA_decimal_value) - rate_decimals)
            );
        } else if (decimal_value::decimal(&coinA_decimal_value) < rate_decimals) {
            rate = decimal_value::new(
                rate_value / (math::pow(10, rate_decimals - decimal_value::decimal(&coinA_decimal_value)) as u64),
                rate_decimals - (rate_decimals - decimal_value::decimal(&coinA_decimal_value))
            );
        }
        else {
            rate = decimal_value::new(
                rate_value,
                rate_decimals
            );
        };

        let coinA_updated_value = subtract(&mut coinA_decimal_value, &decimal_value::new(amount, rate_decimals));
        set_coin_amount(fantasy_wallet, coinA, coinA_updated_value);

        let exchange_res = multiply(&mut decimal_value::new(amount, rate_decimals), &rate);
        let exchange_res = devide(&mut exchange_res, &decimal_value::new(math::pow(10, decimal_value::decimal(&coinA_decimal_value)), rate_decimals));
        let coinB_updated_value = add(&mut coinB_decimal_value, &exchange_res);
        set_coin_amount(fantasy_wallet, coinB, coinB_updated_value);
    }

    fun simple_oracle_get_latest_data(
        oracle: &SimpleOracle,
        coinA: String,
        coinB: String
    ): Option<Data<DecimalValue>> {

        assert!(
            (coinA == string::utf8(b"btc") && coinB == string::utf8(b"usd")) ||
            (coinA == string::utf8(b"eth") && coinB == string::utf8(b"dai")) ||
            (coinA == string::utf8(b"eth") && coinB == string::utf8(b"usd")) ||
            (coinA == string::utf8(b"sui") && coinB == string::utf8(b"btc")) ||
            (coinA == string::utf8(b"sui") && coinB == string::utf8(b"eur")) ||
            (coinA == string::utf8(b"sui") && coinB == string::utf8(b"usd")) ||
            (coinA == string::utf8(b"usdc") && coinB == string::utf8(b"usd")) ||
            (coinA == string::utf8(b"wbtc") && coinB == string::utf8(b"eth")),
            EUnsupportedExchange
        );

        let ticker = coinA;
        string::append(&mut ticker, utf8(b"/"));
        string::append(&mut ticker, coinB);
        string::append(&mut ticker, utf8(b"-binance"));

        simple_oracle::get_latest_data<DecimalValue>(oracle, ticker)
    }

    fun get_coin_decimal_value(
        fantasy_wallet: &mut FantasyWallet,
        coin: String,
    ): DecimalValue {
        if (string::bytes(&coin) == string::bytes(&string::utf8(b"btc")))
            fantasy_wallet.btc
        else if (string::bytes(&coin) == string::bytes(&string::utf8(b"dai")))
            fantasy_wallet.dai
        else if (string::bytes(&coin) == string::bytes(&string::utf8(b"eth")))
            fantasy_wallet.eth
        else if (string::bytes(&coin) == string::bytes(&string::utf8(b"eur")))
            fantasy_wallet.eur
        else if (string::bytes(&coin) == string::bytes(&string::utf8(b"sui")))
            fantasy_wallet.sui
        else if (string::bytes(&coin) == string::bytes(&string::utf8(b"usd")))
            fantasy_wallet.usd
        else if (string::bytes(&coin) == string::bytes(&string::utf8(b"usdc")))
            fantasy_wallet.usdc
        else
            fantasy_wallet.wbtc
    }

    fun set_coin_amount(
        fantasy_wallet: &mut FantasyWallet,
        coin: String,
        decimal_value: DecimalValue
    ) {
        if (string::bytes(&coin) == string::bytes(&string::utf8(b"btc")))
            fantasy_wallet.btc = decimal_value;
        if (string::bytes(&coin) == string::bytes(&string::utf8(b"dai")))
            fantasy_wallet.dai = decimal_value;
        if (string::bytes(&coin) == string::bytes(&string::utf8(b"eth")))
            fantasy_wallet.eth = decimal_value;
        if (string::bytes(&coin) == string::bytes(&string::utf8(b"eur")))
            fantasy_wallet.eur = decimal_value;
        if (string::bytes(&coin) == string::bytes(&string::utf8(b"sui")))
            fantasy_wallet.sui = decimal_value;
        if (string::bytes(&coin) == string::bytes(&string::utf8(b"usd")))
            fantasy_wallet.usd = decimal_value;
        if (string::bytes(&coin) == string::bytes(&string::utf8(b"usdc")))
            fantasy_wallet.usdc = decimal_value;
        if (string::bytes(&coin) == string::bytes(&string::utf8(b"wbtc")))
            fantasy_wallet.wbtc = decimal_value;
    }

    fun add(
        self: &mut DecimalValue, 
        other: &DecimalValue
    ): DecimalValue {
        if (decimal_value::decimal(self) != decimal_value::decimal(other)) {
            // Return an error or convert one of the values to have the same number of decimals as the other
        };
        let new_value = decimal_value::value(self) + decimal_value::value(other);
        decimal_value::new(new_value, decimal_value::decimal(self))
    }

    fun subtract(
        self: &mut DecimalValue, 
        other: &DecimalValue
    ): DecimalValue {
        if (decimal_value::decimal(self) != decimal_value::decimal(other)) {
            // Return an error or convert one of the values to have the same number of decimals as the other
        };
        let new_value = decimal_value::value(self) - decimal_value::value(other);
        decimal_value::new(new_value, decimal_value::decimal(self))
    }

    fun multiply(
        self: &mut DecimalValue, 
        other: &DecimalValue
    ): DecimalValue {
        if (decimal_value::decimal(self) != decimal_value::decimal(other)) {
            // Return an error or convert one of the values to have the same number of decimals as the other
        };
        let new_value = decimal_value::value(self) * decimal_value::value(other);
        decimal_value::new(new_value, decimal_value::decimal(self))
    }

    fun devide(
        self: &mut DecimalValue, 
        other: &DecimalValue
    ): DecimalValue {
        if (decimal_value::decimal(self) != decimal_value::decimal(other)) {
            // Return an error or convert one of the values to have the same number of decimals as the other
        };
        let new_value = decimal_value::value(self) / decimal_value::value(other);
        decimal_value::new(new_value, decimal_value::decimal(self))
    }

    public fun btc(self: &FantasyWallet): DecimalValue { self.btc }
    public fun dai(self: &FantasyWallet): DecimalValue { self.dai }
    public fun eth(self: &FantasyWallet): DecimalValue { self.eth }
    public fun eur(self: &FantasyWallet): DecimalValue { self.eur }
    public fun sui(self: &FantasyWallet): DecimalValue { self.sui }
    public fun usd(self: &FantasyWallet): DecimalValue { self.usd }
    public fun usdc(self: &FantasyWallet): DecimalValue { self.usdc }
    public fun wbtc(self: &FantasyWallet): DecimalValue { self.wbtc }

    #[test_only]
    public fun mint_for_testing(ctx: &mut TxContext): FantasyWallet {
        FantasyWallet {
            id: object::new(ctx),
            btc: decimal_value::new(1_000_000, 4),
            dai: decimal_value::new(1_000_000, 4),
            eth: decimal_value::new(1_000_000, 4),
            eur: decimal_value::new(1_000_000, 4),
            sui: decimal_value::new(1_000_000, 4),
            usd: decimal_value::new(1_000_000, 4),
            usdc: decimal_value::new(1_000_000, 4),
            wbtc: decimal_value::new(1_000_000, 4),
        }
    }

    #[test_only]
    public fun burn_for_testing(fantasy_wallet: FantasyWallet) {
        let FantasyWallet {
            id,
            btc: _,
            dai: _,
            eth: _,
            eur: _,
            sui: _,
            usd: _,
            usdc: _,
            wbtc: _,
        } = fantasy_wallet;
        object::delete(id)
    }

    #[test_only]
    public fun swap_for_testing(
        fantasy_wallet: &mut FantasyWallet,
        coinA: String,
        coinB: String,
        amount: u64
    ) {
        let coinA_decimal_value = get_coin_decimal_value(fantasy_wallet, coinA);
        let coinB_decimal_value = get_coin_decimal_value(fantasy_wallet, coinB);

        assert!(decimal_value::value(&coinA_decimal_value) >= amount, EInsufficientAmount);

        let rate = decimal_value::new(500000, 6);
        let rate_decimals = decimal_value::decimal(&rate);

        if (decimal_value::decimal(&coinA_decimal_value) > rate_decimals) {
            rate = decimal_value::new(
                decimal_value::value(&rate) * (math::pow(10, decimal_value::decimal(&coinA_decimal_value) - rate_decimals) as u64),
                decimal_value::decimal(&rate) + (decimal_value::decimal(&coinA_decimal_value) - rate_decimals)
            );
        } else if (decimal_value::decimal(&coinA_decimal_value) < rate_decimals) {
            rate = decimal_value::new(
                decimal_value::value(&rate) / (math::pow(10, rate_decimals - decimal_value::decimal(&coinA_decimal_value)) as u64),
                decimal_value::decimal(&rate) - (rate_decimals - decimal_value::decimal(&coinA_decimal_value))
            );
        };

        let coinA_updated_value = subtract(&mut coinA_decimal_value, &decimal_value::new(amount, rate_decimals));
        set_coin_amount(fantasy_wallet, coinA, coinA_updated_value);

        let exchange_res = multiply(&mut decimal_value::new(amount, rate_decimals), &rate);
        let exchange_res = devide(&mut exchange_res, &decimal_value::new(math::pow(10, decimal_value::decimal(&coinA_decimal_value)), rate_decimals));
        let coinB_updated_value = add(&mut coinB_decimal_value, &exchange_res);
        set_coin_amount(fantasy_wallet, coinB, coinB_updated_value);
    }
}
