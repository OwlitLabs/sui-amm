module owlswap_amm::router {

    use owlswap_amm::control::{Self, Store, get_name};
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
    use sui::clock::{Clock, timestamp_ms};
    use sui::math;


    const E_X_Y_ERROR: u64 = 600;
    const E_POOL_EXSIT: u64 = 601;
    //const E_X_Y_NOT_SORTED: u64 = 602;
    const E_LP_AMOUNT_ERROR: u64 = 603;
    const E_IN_AMOUNT_ERROR: u64 = 604;
    const E_X_Y_SAME: u64 = 605;
    const E_MUST_HAV_X_COIN : u64 = 606;
    const E_MUST_HAV_Y_COIN : u64 = 607;

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
        x_fee: u32,
        x_coin_check: &Coin<X>,
        y_decimals: u8,
        y_fee: u32,
        y_coin_check: &Coin<Y>,
        trading_time: u64,
        ctx: &mut TxContext) {

        control::check_version(store);

        assert!(coin::value(x_coin_check) > 0, E_MUST_HAV_X_COIN);
        assert!(coin::value(y_coin_check) > 0, E_MUST_HAV_Y_COIN);

        let x_scale = math::pow(10, x_decimals);
        let y_scale = math::pow(10, y_decimals);

        let pool_id: ID;

        if(is_type_sorted<X, Y>()) {
            assert!(!control::exist<X, Y>(store), E_POOL_EXSIT);
            pool_id = pool::create_pool<X, Y>(clock_target, x_scale, x_fee, y_scale, y_fee, trading_time, ctx);
            control::add<X, Y>(store, pool_id, sender(ctx));
        } else {
            assert!(!control::exist<Y, X>(store), E_POOL_EXSIT);
            pool_id = pool::create_pool<Y, X>(clock_target, x_scale, x_fee, y_scale, y_fee, trading_time, ctx);
            control::add<Y, X>(store, pool_id, sender(ctx));
        };

        events::emit_pool_created(pool_id, get_name<X>(), get_name<Y>());
    }

    entry fun add_liquidity<X, Y>(
        store: &mut Store,
        pool: &mut Pool<X, Y>,
        x_coins: vector<Coin<X>>,
        x_amount: u64,
        x_min: u64,
        y_coins: vector<Coin<Y>>,
        y_amount: u64,
        y_min: u64,
        ctx: &mut TxContext) {

        control::check_version(store);

        assert!(x_amount > 0 && x_amount > 0, E_X_Y_ERROR);

        let x_coin = coin::zero<X>(ctx);
        let y_coin = coin::zero<Y>(ctx);

        pay::join_vec(&mut x_coin, x_coins);
        pay::join_vec(&mut y_coin, y_coins);

        let x_coin_real = coin::split(&mut x_coin, x_amount, ctx);
        let y_coin_real = coin::split(&mut y_coin, y_amount, ctx);

        let (lp_coin, x_coin_value, y_coin_value, tx_index) = pool::add_liquidity(
            pool,
            x_coin_real,
            x_min,
            y_coin_real,
            y_min,
            ctx
        );

        let lp_value = coin::value(&lp_coin);

        if(coin::value(&x_coin) > 0) {
            transfer::public_transfer(x_coin, sender(ctx));
        } else {
            coin::destroy_zero(x_coin);
        };
        if(coin::value(&y_coin) > 0) {
            transfer::public_transfer(y_coin, sender(ctx));
        } else {
            coin::destroy_zero(y_coin);
        };

        transfer::public_transfer(lp_coin, sender(ctx));
        events::emit_liqudity_added(id(pool), x_coin_value, y_coin_value, lp_value, tx_index);
    }

    entry fun remove_liquidity<X, Y>(
        store: &mut Store,
        pool: &mut Pool<X, Y>,
        lp_coins: vector<Coin<LP<X, Y>>>,
        lp_amount: u64,
        ctx: &mut TxContext) {

        control::check_version(store);

        assert!(lp_amount > 0, E_LP_AMOUNT_ERROR);

        let lp_coin = coin::zero<LP<X, Y>>(ctx);
        pay::join_vec(&mut lp_coin, lp_coins);

        let lp_real = coin::split(&mut lp_coin, lp_amount, ctx);

        let (burned_amount, x_coin, y_coin, tx_index) = pool::remove_liqudity(pool, lp_real, ctx);

        let x_value = coin::value(&x_coin);
        let y_value = coin::value(&y_coin);

        transfer::public_transfer(x_coin, sender(ctx));
        transfer::public_transfer(y_coin, sender(ctx));

        if (coin::value(&lp_coin) > 0) {
            transfer::public_transfer(lp_coin, sender(ctx));
        } else {
            coin::destroy_zero(lp_coin);
        };

        events::emit_liqudity_removed(id(pool), x_value, y_value, burned_amount, tx_index);
    }

    entry fun swap_x_to_y<X, Y>(
        store: &mut Store,
        pool: &mut Pool<X, Y>,
        clock_target: &Clock,
        x_coins: vector<Coin<X>>,
        x_amount: u64,
        y_min_out: u64,
        ctx: &mut TxContext
    ) {
        control::check_version(store);

        assert!(x_amount > 0, E_IN_AMOUNT_ERROR);

        let x_coin = coin::zero<X>(ctx);
        pay::join_vec(&mut x_coin, x_coins);

        let x_coin_real = coin::split(&mut x_coin, x_amount, ctx);

        let  (y_coin, tx_index) = pool::swap_x_to_y(pool, clock_target, x_coin_real, y_min_out, ctx);

        let y_amount = coin::value(&y_coin);

        if (coin::value(&x_coin) > 0) {
            transfer::public_transfer(x_coin, sender(ctx));
        } else {
            coin::destroy_zero(x_coin);
        };

        transfer::public_transfer(y_coin, sender(ctx));

        events::emit_swap(id(pool), sender(ctx), x_amount, 0, 0, y_amount, tx_index);
    }

    entry fun swap_y_to_x<X, Y>(
        store: &mut Store,
        pool: &mut Pool<X, Y>,
        clock_target: &Clock,
        y_coins: vector<Coin<Y>>,
        y_amount: u64,
        x_min_out: u64,
        ctx: &mut TxContext
    ) {
        control::check_version(store);

        assert!(y_amount > 0, E_IN_AMOUNT_ERROR);

        let y_coin = coin::zero<Y>(ctx);
        pay::join_vec(&mut y_coin, y_coins);

        let y_coin_real = coin::split(&mut y_coin, y_amount, ctx);

        let (x_coin, tx_index) = pool::swap_y_to_x(pool, clock_target, y_coin_real, x_min_out, ctx);

        let x_amount = coin::value(&x_coin);

        if (coin::value(&y_coin) > 0) {
            transfer::public_transfer(y_coin, sender(ctx));
        } else {
            coin::destroy_zero(y_coin);
        };

        transfer::public_transfer(x_coin, sender(ctx));

        events::emit_swap(id(pool), sender(ctx), 0, x_amount, y_amount, 0, tx_index);
    }


    entry fun withdraw<X, Y>(store: &mut Store, pool: &mut Pool<X, Y>,  recipient: address, ctx: &mut TxContext) {

        control::check_version(store);

        let (x_coin, y_coin) = pool::withdraw_pool_fee(pool, ctx);

        if (recipient == @zero) {
            recipient = sender(ctx);
        };

        let x_value = coin::value(&x_coin);
        let y_value = coin::value(&y_coin);

        transfer::public_transfer(x_coin, recipient);
        transfer::public_transfer(y_coin, recipient);

        events::emit_pool_fee_withdraw(id(pool), x_value, y_value, recipient);
    }

    entry fun update_pool_fee<X, Y>(
        store: &mut Store,
        pool: &mut Pool<X, Y>,
        clock_target: &Clock,
        x_fee_rate: u32,
        y_fee_rate: u32,
        ctx: &mut TxContext) {

        control::check_version(store);

        let (old_x, old_y, new_x, new_y) = pool::update_pool_fee_config(pool, x_fee_rate, y_fee_rate, ctx);
        events::emit_pool_fee_config_updated(id(pool), old_x, old_y, new_x, new_y, timestamp_ms(clock_target));
    }

    entry fun update_pool_owner<X, Y>(
        store: &mut Store,
        pool: &mut Pool<X, Y>,
        new_owner: address,
        ctx: &mut TxContext) {

        control::check_version(store);

        let old_onwer = pool::update_owner(pool, new_owner, ctx);
        control::owner_change(store, id(pool), old_onwer, new_owner);
        events::emit_pool_owner_updated(id(pool), old_onwer, new_owner);
    }

}