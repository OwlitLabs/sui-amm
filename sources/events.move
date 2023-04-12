module owlswap_amm::events {

    use sui::event;
    use sui::object::{ID};
    use std::string::String;
    use sui::event::emit;
    friend owlswap_amm::pool;

    struct PoolCreated has drop, copy {
        pool_id: ID,
        sender: address,
        lp_name: String
    }

    public fun emit_pool_created(pool_id: ID, sender: address, lp_name: String) {
        event::emit(PoolCreated{
            pool_id,
            sender,
            lp_name
        });
    }

    struct LiquidityAdded has drop, copy {
        pool_id: ID,
        x_amount: u64,
        y_amount: u64,
        lp_amount: u64,
    }

    public fun emit_liqudity_added(pool_id: ID, x_amount: u64, y_amount: u64, lp_amount: u64) {
        event::emit(LiquidityAdded{
            pool_id,
            x_amount,
            y_amount,
            lp_amount
        })
    }

    struct LiquidityRemoved has drop, copy {
        pool_id: ID,
        x_amount: u64,
        y_amount: u64,
        lp_amount: u64,
    }

    public fun emit_liqudity_removed(pool_id: ID, x_amount: u64, y_amount: u64, lp_amount: u64) {
        event::emit(LiquidityAdded{
            pool_id,
            x_amount,
            y_amount,
            lp_amount
        })
    }

    struct Swaped has drop, copy {
        pool_id: ID,
        sender: address,
        x_in: u64,
        x_out: u64,
        y_in: u64,
        y_out: u64,
        time: u64
    }

    public fun emit_swap(pool_id: ID, sender: address, x_in: u64, x_out: u64, y_in: u64, y_out: u64, time: u64) {
        emit(Swaped{
            pool_id,
            sender,
            x_in,
            x_out,
            y_in,
            y_out,
            time
        })
    }

    struct FundationFeeWithdrawal has drop, copy {
        pool_id: ID,
        x_amount: u64,
        y_amount: u64,
        recipient: address
    }

    public fun emit_fundation_fee_withdraw(pool_id: ID, x_amount: u64, y_amount: u64, recipient: address) {
        event::emit(FundationFeeWithdrawal{
            pool_id,
            x_amount,
            y_amount,
            recipient
        });
    }

    struct PromoterFeeWithdraw has drop, copy {
        pool_id: ID,
        x_amount: u64,
        y_amount: u64,
        recipient: address
    }
    public fun emit_promoter_fee_withdraw(pool_id: ID, x_amount: u64, y_amount: u64, recipient: address) {
        event::emit(PromoterFeeWithdraw{
            pool_id,
            x_amount,
            y_amount,
            recipient
        });
    }

    struct PoolFeeUpdated has drop, copy {
        pool_id: ID,
        old_fee: u64,
        new_fee: u64
    }
    public fun emit_pool_fee_updated(pool_id: ID, old_fee: u64, new_fee: u64) {
        event::emit(PoolFeeUpdated{
            pool_id,
            old_fee,
            new_fee
        });
    }

    struct PoolOwnerUpdated has drop, copy {
        pool_id: ID,
        old_owner: address,
        new_owner: address
    }
    public fun emit_pool_owner_updated(pool_id: ID, old_owner: address, new_owner: address) {
        event::emit(PoolOwnerUpdated{
            pool_id,
            old_owner,
            new_owner
        });
    }

    struct Test has drop, copy{
        time:u64
    }
    public fun test(time: u64) {
        event::emit(Test{time})
    }
}