module owlswap_amm::router {

    use owlswap_amm::control::{Self, Store};
    use sui::tx_context::{TxContext, sender};
    use owlswap_amm::pool::{Self, Pool, LP};
    use sui::coin::{Coin};
    use sui::coin;
    use sui::pay;
    use sui::transfer;
    use owlswap_amm::events;
    use owlswap_amm::comparator;
    use std::type_name::get;
    use sui::object::{id, ID};
    use sui::clock::Clock;
    use sui::clock;
    use std::string::String;

    #[test_only]
    use std::debug::print;
    use sui::math;


    const E_X_Y_ERROR: u64 = 600;
    const E_POOL_EXSIT: u64 = 601;
    //const E_X_Y_NOT_SORTED: u64 = 602;
    const E_LP_AMOUNT_ERROR: u64 = 603;
    const E_IN_AMOUNT_ERROR: u64 = 604;
    const E_X_Y_SAME: u64 = 605;

    fun is_type_sorted<X, Y>(): bool {
        let comp = comparator::compare(&get<X>(), &get<Y>());
        assert!(!comparator::is_equal(&comp), E_X_Y_SAME);
        if (comparator::is_smaller_than(&comp)) {
            true
        } else {
            false
        }
    }

    entry fun create_pool<X, Y>(
        store: &mut Store,
        clock_target: &Clock,
        x_decimals: u8,
        x_fee: u64,
        y_decimals: u8,
        y_fee: u64,
        ctx: &mut TxContext) {
        //assert!(is_type_sorted<X, Y>(), E_X_Y_NOT_SORTED);

        let x_scale = math::pow(10, x_decimals);
        let y_scale = math::pow(10, y_decimals);

        let pool_id: ID;
        let lp_name: String;
        if(is_type_sorted<X, Y>()) {
            assert!(!control::exist<X, Y>(store), E_POOL_EXSIT);
            pool_id = pool::create_pool<X, Y>(clock_target, x_scale, x_fee, y_scale, y_fee, ctx);
            lp_name = control::add<X, Y>(store, pool_id, sender(ctx));
        } else {
            assert!(!control::exist<Y, X>(store), E_POOL_EXSIT);
            pool_id = pool::create_pool<Y, X>(clock_target, x_scale, x_fee, y_scale, y_fee, ctx);
            lp_name = control::add<Y, X>(store, pool_id, sender(ctx));
        };
        events::emit_pool_created(pool_id, sender(ctx), lp_name);
    }

    entry fun add_liquidity<X, Y>(
        pool: &mut Pool<X, Y>,
        x_coins: vector<Coin<X>>,
        x_amount: u64,
        x_min: u64,
        y_coins: vector<Coin<Y>>,
        y_amount: u64,
        y_min: u64,
        ctx: &mut TxContext) {
        assert!(x_amount > 0 && x_amount > 0, E_X_Y_ERROR);

        let x_coin = coin::zero<X>(ctx);
        let y_coin = coin::zero<Y>(ctx);

        pay::join_vec(&mut x_coin, x_coins);
        pay::join_vec(&mut y_coin, y_coins);

        let x_coin_real = coin::split(&mut x_coin, x_amount, ctx);
        let y_coin_real = coin::split(&mut y_coin, y_amount, ctx);

        let (lp_coin, x_coin_last, y_coin_last) = pool::add_liquidity(
            pool,
            x_coin_real,
            x_min,
            y_coin_real,
            y_min,
            ctx
        );

        coin::join(&mut x_coin, x_coin_last);
        coin::join(&mut y_coin, y_coin_last);

        if (coin::value(&x_coin) > 0) {
            transfer::public_transfer(x_coin, sender(ctx));
        } else {
            coin::destroy_zero(x_coin);
        };

        if (coin::value(&y_coin) > 0) {
            transfer::public_transfer(y_coin, sender(ctx));
        } else {
            coin::destroy_zero(y_coin);
        };

        transfer::public_transfer(lp_coin, sender(ctx));
        events::emit_liqudity_added(id(pool), 0, 0, 0);
    }

    entry fun remove_liquidity<X, Y>(
        pool: &mut Pool<X, Y>,
        lp_coins: vector<Coin<LP<X, Y>>>,
        lp_amount: u64,
        ctx: &mut TxContext) {
        assert!(lp_amount > 0, E_LP_AMOUNT_ERROR);

        let lp_coin = coin::zero<LP<X, Y>>(ctx);
        pay::join_vec(&mut lp_coin, lp_coins);

        let lp_real = coin::split(&mut lp_coin, lp_amount, ctx);

        let (burned_amount, x_coin, y_coin) = pool::remove_liqudity(pool, lp_real, ctx);

        transfer::public_transfer(x_coin, sender(ctx));
        transfer::public_transfer(y_coin, sender(ctx));
        if (coin::value(&lp_coin) > 0) {
            transfer::public_transfer(lp_coin, sender(ctx));
        } else {
            coin::destroy_zero(lp_coin);
        };

        events::emit_liqudity_removed(id(pool), 0, 0, burned_amount);
    }

    entry fun swap_x_to_y<X, Y>(
        pool: &mut Pool<X, Y>,
        clock_target: &Clock,
        x_coins: vector<Coin<X>>,
        x_amount: u64,
        y_min_out: u64,
        ctx: &mut TxContext
    ) {
        assert!(x_amount > 0, E_IN_AMOUNT_ERROR);

        let x_coin = coin::zero<X>(ctx);
        pay::join_vec(&mut x_coin, x_coins);

        let x_coin_real = coin::split(&mut x_coin, x_amount, ctx);

        let  y_coin = pool::swap_x_to_y(pool, x_coin_real, y_min_out, ctx);

        let y_amount = coin::value(&y_coin);

        if (coin::value(&x_coin) > 0) {
            transfer::public_transfer(x_coin, sender(ctx));
        } else {
            coin::destroy_zero(x_coin);
        };

        transfer::public_transfer(y_coin, sender(ctx));

        events::emit_swap(id(pool), sender(ctx), x_amount, 0, 0, y_amount, clock::timestamp_ms(clock_target));
    }

    entry fun swap_y_to_x<X, Y>(
        pool: &mut Pool<X, Y>,
        clock_target: &Clock,
        y_coins: vector<Coin<Y>>,
        y_amount: u64,
        x_min_out: u64,
        ctx: &mut TxContext
    ) {
        assert!(y_amount > 0, E_IN_AMOUNT_ERROR);

        let y_coin = coin::zero<Y>(ctx);
        pay::join_vec(&mut y_coin, y_coins);

        let y_coin_real = coin::split(&mut y_coin, y_amount, ctx);

        let x_coin = pool::swap_y_to_x(pool, y_coin_real, x_min_out, ctx);

        let x_amount = coin::value(&x_coin);

        if (coin::value(&y_coin) > 0) {
            transfer::public_transfer(y_coin, sender(ctx));
        } else {
            coin::destroy_zero(y_coin);
        };

        transfer::public_transfer(x_coin, sender(ctx));

        events::emit_swap(id(pool), sender(ctx), 0, x_amount, y_amount, 0, clock::timestamp_ms(clock_target));
    }


    entry fun withdraw<X, Y>(pool: &mut Pool<X, Y>, recipient: address, ctx: &mut TxContext) {
        let (x_coin, y_coin) = pool::withdraw_promoter_fee(pool, ctx);

        if (recipient == @zero) {
            recipient = sender(ctx);
        };

        let x_value = coin::value(&x_coin);
        let y_value = coin::value(&y_coin);

        transfer::public_transfer(x_coin, recipient);
        transfer::public_transfer(y_coin, recipient);

        events::emit_promoter_fee_withdraw(id(pool), x_value, y_value, recipient);
    }

    entry fun update_pool_fee<X, Y>(
        pool: &mut Pool<X, Y>,
        x_fee: u64,
        y_fee: u64,
        ctx: &mut TxContext) {
        pool::update_fee(pool, x_fee, y_fee, ctx);
        events::emit_pool_fee_updated(id(pool), x_fee, y_fee);
    }

    entry fun update_pool_owner<X, Y>(
        store: &mut Store,
        pool: &mut Pool<X, Y>,
        new_owner: address,
        ctx: &mut TxContext) {
        let old_onwer = pool::update_owner(pool, new_owner, ctx);
        control::owner_change(store, id(pool), old_onwer, new_owner);
        events::emit_pool_owner_updated(id(pool), old_onwer, new_owner);
    }

    public entry fun test_event() {
        events::test(1);
    }

    // === Test-only code ===
    #[test]
    public fun test_create_pool() {




        print(&2);
    }
}