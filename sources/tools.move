module owlswap_amm::tools {
    use owlswap_amm::maths;

    const E_INSUFFICIENT_INPUT : u64 = 701;
    const E_INSUFFICIENT_LIQUIDITY : u64 = 702;
    const E_INCORRECT_SWAP : u64 = 703;
    const E_INSUFFICIENT_COIN_X : u64 = 704;
    const E_INSUFFICIENT_COIN_Y : u64 = 705;
    const E_LIQ_OVER_LIMIT : u64 = 706;

    public fun get_fee(
        in_amount: u64,
        fee_rate: u32,
        fee_scale: u32,
    ): u64 {
        // transcation fee to leader
        maths::mul_div(in_amount, (fee_rate as u64), (fee_scale as u64))
    }

    public fun calculate_amount_out(in_reserve: u64, out_reserve: u64, in_amount: u64): u64 {
        // Input validation.
        assert!(in_amount > 0, E_INSUFFICIENT_INPUT);
        assert!(in_reserve > 0 && out_reserve > 0, E_INSUFFICIENT_LIQUIDITY);

        // Calculate the amount of asset2 to buy.
        let numerator = (in_amount as u128) * (out_reserve as u128);
        let denominator = (in_reserve as u128) + (in_amount as u128);

        // Return the amount of asset2 to buy.
        (numerator/denominator as u64)
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

    public fun calc_optimal_values(
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
            let y_returned =  maths::mul_div(x_desired, y_reserve, x_reserve);
            if (y_returned <= y_desired) {
                assert!(y_returned >= y_min, E_INSUFFICIENT_COIN_Y);
                return (x_desired, y_returned)
            } else {
                let x_returned = maths::mul_div(y_desired, x_reserve, y_reserve);
                assert!(x_returned <= x_desired, E_LIQ_OVER_LIMIT);
                assert!(x_returned >= x_min, E_INSUFFICIENT_COIN_X);
                return (x_returned, y_desired)
            }
        }
    }
}