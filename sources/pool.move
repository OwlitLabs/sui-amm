module owlswap_amm::pool {

    use sui::tx_context::{TxContext, sender};
    use sui::object::{ID, UID};
    use sui::object;
    use sui::transfer;
    use sui::coin::{Coin};
    use sui::balance::{Balance, Supply};
    use sui::balance;
    use sui::coin;
    use owlswap_amm::maths;
    use sui::clock::{Clock, timestamp_ms};


    const U64_MAX : u64 = 18446744073709551615;
    /// Minimal liquidity.
    const MINIMAL_LIQUIDITY : u64 = 1000;
    /// Current fee is 0.3%
    const FEE_FOUNDATION: u64 = 30;
    /// The integer scaling setting for fees calculation.
    const FEE_SCALE: u64 = 10000;
    /// The max value that can be held in one of the Balances of
    /// a Pool. U64 MAX / FEE_SCALE
    const MAX_POOL_VALUE: u64 = {
        18446744073709551615 / 10000
    };


    const E_NOT_AUTHORIZED : u64 = 99;

    const E_DIVIDE_BY_ZERO : u64 = 500;
    const E_U64_OVERFLOW : u64 = 501;
    const E_INSUFFICIENT_COIN_X : u64 = 502;
    const E_INSUFFICIENT_COIN_Y : u64 = 503;
    const E_LIQ_OVER_LIMIT : u64 = 504;
    const E_LIQUID_NOT_ENOUGH : u64 = 505;
    const E_INSUFFICIENT_LIQUIDITY_MINTED : u64 = 506;
    const E_POOL_FULL : u64 = 507;
    const E_REMOVE_OUT_ERROR : u64 = 508;
    const E_RESERVES_EMPTY : u64 = 509;
    const E_MIN_OUT_LIMIT : u64 = 510;
    const E_WITHDRAW_FEE_INSUFFICIENT : u64 = 511;
    const E_INCORRECT_SWAP : u64 = 512;
    const E_INSUFFICIENT_INPUT : u64 = 513;
    const E_INSUFFICIENT_LIQUIDITY : u64 = 514;




    struct LP<phantom X, phantom Y> has drop {
    }

    struct Pool<phantom X, phantom Y> has key {
        id: UID,
        owner: address,

        x_reserve: Balance<X>,              //X reserve amount
        x_fee_percent: u64,                 //
        x_promoter: Balance<X>,
        x_foundation: Balance<X>,
        x_scale: u64,

        y_reserve: Balance<Y>,
        y_fee_percent: u64,
        y_promoter: Balance<Y>,
        y_foundation: Balance<Y>,
        y_scale: u64,

        lp_supply: Supply<LP<X, Y>>,
        min_liquidity: Balance<LP<X, Y>>,

        create_time: u64,
        trading_time: u64,

    }

    public fun create_pool<X, Y>(clock: &Clock, x_scale: u64, x_fee: u64, y_scale: u64 ,y_fee: u64, ctx: &mut TxContext) : ID {
        let pool = Pool<X, Y> {
            id: object::new(ctx),
            owner: sender(ctx),

            x_reserve: balance::zero<X>(),
            x_fee_percent: x_fee,
            x_promoter: balance::zero<X>(),
            x_foundation: balance::zero<X>(),
            x_scale,

            y_reserve: balance::zero<Y>(),
            y_fee_percent: y_fee,
            y_promoter: balance::zero<Y>(),
            y_foundation: balance::zero<Y>(),
            y_scale,

            lp_supply: balance::create_supply(LP<X, Y>{}),
            min_liquidity:balance::zero<LP<X, Y>>(),

            create_time: timestamp_ms(clock),
            trading_time: 0,
        };

        let pool_id = object::id(&pool);
        transfer::share_object(pool);
        pool_id
    }

    public fun add_liquidity<X, Y>(
        pool: &mut Pool<X, Y>,
        x_coin: Coin<X>,
        x_min: u64,
        y_coin: Coin<Y>,
        y_min: u64,
        ctx: &mut TxContext) : (Coin<LP<X, Y>>, Coin<X>, Coin<Y>) {

        let (x_reserve, y_reserve, lp_supply) = get_reserves_size(pool);

        let x_balance = coin::into_balance(x_coin);
        let x_deposit = balance::value(&x_balance);

        let y_balance = coin::into_balance(y_coin);
        let y_deposit = balance::value(&y_balance);

        let (x_optimal, y_optimal) = calc_optimal_values(x_deposit, y_deposit, x_min, y_min, x_reserve, y_reserve);

        let provide_liq = if(lp_supply == 0) {
            let initial_liq = maths::sqrt(maths::mul_to_u128(x_optimal, y_optimal));
            assert!(initial_liq > MINIMAL_LIQUIDITY, E_LIQUID_NOT_ENOUGH);
            let min_liquidity = balance::increase_supply(&mut pool.lp_supply, MINIMAL_LIQUIDITY);
            balance::join(&mut pool.min_liquidity, min_liquidity);

            initial_liq - MINIMAL_LIQUIDITY
        } else {
            let a_liquidity = (lp_supply as u128) * (x_optimal as u128) / (x_reserve as u128);
            let b_liquidity = (lp_supply as u128) * (y_optimal as u128) / (y_reserve as u128);
            if(a_liquidity < b_liquidity) {
                assert!(a_liquidity < (U64_MAX as u128), E_U64_OVERFLOW);
                (a_liquidity as u64)
            } else {
                assert!(b_liquidity < (U64_MAX as u128), E_U64_OVERFLOW);
                (b_liquidity as u64)
            }
        };

        assert!(provide_liq > 0, E_INSUFFICIENT_LIQUIDITY_MINTED);

        let x_last = balance::zero<X>();
        let y_last = balance::zero<Y>();

        if(x_optimal < x_deposit) {
            balance::join(&mut x_last, balance::split(&mut x_balance, x_deposit - x_optimal));
        };
        if(y_optimal < y_deposit) {
            balance::join(&mut y_last, balance::split(&mut y_balance, y_deposit - y_optimal));
        };

        let x_new_reserve = balance::join(&mut pool.x_reserve, x_balance);
        let y_new_reserve = balance::join(&mut pool.y_reserve, y_balance);

        assert!(x_new_reserve < MAX_POOL_VALUE, E_POOL_FULL);
        assert!(y_new_reserve < MAX_POOL_VALUE, E_POOL_FULL);

        let lp_balance = balance::increase_supply(&mut pool.lp_supply, provide_liq);

        (coin::from_balance(lp_balance, ctx), coin::from_balance(x_last, ctx), coin::from_balance(y_last, ctx))
    }

    public fun remove_liqudity<X, Y>(pool: &mut Pool<X, Y>, lp_coin: Coin<LP<X, Y>>, ctx: &mut TxContext) : (u64, Coin<X>, Coin<Y>){
        let lp_value = coin::value(&lp_coin);

        let (x_reserve, y_reserve, lp_supply) = get_reserves_size(pool);

        let x_out = quote(x_reserve, lp_value, lp_supply);
        let y_out = quote(y_reserve, lp_value, lp_supply);

        assert!(x_out > 0 && y_out > 0, E_REMOVE_OUT_ERROR);

        let burned_amount = balance::decrease_supply(&mut pool.lp_supply, coin::into_balance(lp_coin));

        (burned_amount, coin::take(&mut pool.x_reserve, x_out, ctx), coin::take(&mut pool.y_reserve, y_out, ctx))
    }

    public fun swap_x_to_y<X, Y>(pool: &mut Pool<X, Y>, x_coin: Coin<X>, y_min_out: u64, ctx: &mut TxContext) : Coin<Y> {

        let (x_reserve, y_reserve, _) = get_reserves_size(pool);
        assert!(x_reserve > 0 && y_reserve > 0, E_RESERVES_EMPTY);

        let x_in_value = coin::value(&x_coin);
        let x_fee_foundation = get_fee(x_in_value, FEE_FOUNDATION);
        let x_fee_promoter = get_fee(x_in_value, pool.x_fee_percent);

        let x_in_real_value = x_in_value - x_fee_foundation - x_fee_promoter;

        let y_out_amount = calculate_amount_out(x_reserve, y_reserve, x_in_real_value);
        assert!(y_out_amount >= y_min_out, E_MIN_OUT_LIMIT);

        let x_balance = coin::into_balance(x_coin);
        if(x_fee_foundation > 0) {
            balance::join(&mut pool.x_foundation, balance::split(&mut x_balance, x_fee_foundation));
        };
        if(x_fee_promoter > 0) {
            balance::join(&mut pool.x_promoter, balance::split(&mut x_balance, x_fee_promoter));
        };

        balance::join(&mut pool.x_reserve, x_balance);

        let y_coin = coin::take(&mut pool.y_reserve, y_out_amount, ctx);

        let (x_new_reserve, y_new_reserve, _lp) = get_reserves_size(pool);

        check_reserve_is_increased(x_reserve, y_reserve, x_new_reserve, y_new_reserve);

        y_coin
    }

    public fun swap_y_to_x<X, Y>(pool: &mut Pool<X, Y>, y_coin: Coin<Y>, x_min_out: u64, ctx: &mut TxContext) : Coin<X> {


        let (x_reserve, y_reserve, _) = get_reserves_size(pool);

        assert!(x_reserve > 0 && y_reserve > 0, E_RESERVES_EMPTY);

        let y_in_value = coin::value(&y_coin);

        let y_fee_foundation = get_fee(y_in_value, FEE_FOUNDATION);
        let y_fee_promoter = get_fee(y_in_value, pool.y_fee_percent);

        let y_in_real_value = y_in_value - y_fee_foundation - y_fee_promoter;

        let x_out_amount = calculate_amount_out(y_reserve, x_reserve, y_in_real_value);

        assert!(x_out_amount >= x_min_out, E_MIN_OUT_LIMIT);

        let y_balance = coin::into_balance(y_coin);
        if(y_fee_foundation > 0) {
            balance::join(&mut pool.y_foundation, balance::split(&mut y_balance, y_fee_foundation));
        };
        if(y_fee_promoter > 0) {
            balance::join(&mut pool.y_promoter, balance::split(&mut y_balance, y_fee_promoter));
        };

        balance::join(&mut pool.y_reserve, y_balance);

        let x_coin = coin::take(&mut pool.x_reserve, x_out_amount, ctx);

        let (x_new_reserve, y_new_reserve, _lp) = get_reserves_size(pool);
        check_reserve_is_increased(x_reserve, y_reserve, x_new_reserve, y_new_reserve);

        x_coin
    }

    //==============Pool Management Method==========================

    public fun update_fee<X, Y>(pool: &mut Pool<X, Y>, x_fee: u64, y_fee: u64, ctx: &mut TxContext) {
        check_owner(pool, ctx);
        pool.x_fee_percent = x_fee;
        pool.y_fee_percent = y_fee;
    }

    public fun update_owner<X, Y>(pool: &mut Pool<X, Y>, new_owner: address, ctx: &mut TxContext) : address {
        check_owner(pool, ctx);
        let old_owner = pool.owner;
        pool.owner = new_owner;
        return old_owner
    }

    public fun withdraw_foundation_fee<X, Y>(pool: &mut Pool<X, Y>, ctx: &mut TxContext) : (Coin<X>, Coin<Y>) {

        let x_value = balance::value(&pool.x_foundation);
        let y_value = balance::value(&pool.y_foundation);

        assert!(x_value > 0 && y_value > 0, E_WITHDRAW_FEE_INSUFFICIENT);

        let x_foundation = balance::split(&mut pool.x_foundation, x_value);
        let y_foundation = balance::split(&mut pool.y_foundation, x_value);

        (coin::from_balance(x_foundation, ctx), coin::from_balance(y_foundation, ctx))
    }

    public fun withdraw_promoter_fee<X, Y>(pool: &mut Pool<X, Y>, ctx: &mut TxContext) : (Coin<X>, Coin<Y>) {
        check_owner(pool, ctx);

        let x_value = balance::value(&pool.x_promoter);
        let y_value = balance::value(&pool.y_promoter);

        assert!(x_value > 0 && y_value > 0, E_WITHDRAW_FEE_INSUFFICIENT);

        let x_promoter = balance::split(&mut pool.x_promoter, x_value);
        let y_promoter = balance::split(&mut pool.y_promoter, y_value);

        (coin::from_balance(x_promoter, ctx), coin::from_balance(y_promoter, ctx))
    }

    //==============Private Method==========================

    fun check_owner<X, Y>(pool: &mut Pool<X, Y>, ctx: &mut TxContext) {
        assert!(pool.owner == sender(ctx), E_NOT_AUTHORIZED);
    }


    fun calc_optimal_values(
        x_desired: u64,
        y_desired: u64,
        x_min: u64,
        y_min: u64,
        x_reserve: u64,
        y_reserve: u64
    ): (u64, u64) {
        if (x_reserve == 0 && y_reserve == 0) {
            return (x_desired, y_desired)
        } else {
            let y_returned =  quote(x_desired, y_reserve, x_reserve);
            if (y_returned <= y_desired) {
                assert!(y_returned >= y_min, E_INSUFFICIENT_COIN_Y);
                return (x_desired, y_returned)
            } else {
                let x_returned = quote(y_desired, x_reserve, y_reserve);
                assert!(x_returned <= x_desired, E_LIQ_OVER_LIMIT);
                assert!(x_returned >= x_min, E_INSUFFICIENT_COIN_X);
                return (x_returned, y_desired)
            }
        }
    }

    fun quote(
        x: u64,
        y: u64,
        z: u64
    ): u64 {
        assert!(z != 0, E_DIVIDE_BY_ZERO);
        let r = (x as u128) * (y as u128) / (z as u128);
        assert!(!(r > (U64_MAX as u128)), E_U64_OVERFLOW);
        (r as u64)
    }

    fun get_reserves_size<X, Y>(pool: &mut Pool<X, Y>) : (u64, u64, u64) {
        (
            balance::value(&pool.x_reserve),
            balance::value(&pool.y_reserve),
            balance::supply_value(&pool.lp_supply)
        )
    }

    fun calculate_amount_out(in_reserve: u64, out_reserve: u64, in_amount: u64): u64 {
        // Input validation.
        assert!(in_amount > 0, E_INSUFFICIENT_INPUT);
        assert!(in_reserve > 0 && out_reserve > 0, E_INSUFFICIENT_LIQUIDITY);

        // Calculate the amount of asset2 to buy.
        let amount_in_with_fee = (in_amount as u128);
        let numerator = amount_in_with_fee * (out_reserve as u128);
        let denominator = (in_reserve as u128) + amount_in_with_fee;

        // Return the amount of asset2 to buy.
        (numerator/denominator as u64)
    }

    fun get_fee(
        in_amount: u64,
        fee_percent: u64,
    ): u64 {
        // transcation fee to leader
        maths::mul_div(in_amount, fee_percent, FEE_SCALE)
    }

    public fun check_reserve_is_increased(
        old_reserve_x: u64,
        old_reserve_y: u64,
        new_reserve_x: u64,
        new_reserve_y: u64,
    ) {
        // never overflow
        assert!(
            (old_reserve_x as u128) * (old_reserve_y as u128)
                < (new_reserve_x as u128) * (new_reserve_y as u128),
            E_INCORRECT_SWAP
        )
    }

}