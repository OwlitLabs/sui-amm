
module owlswap_amm::store {

    use sui::object::{UID, ID, id};
    use sui::table::Table;
    use std::string::String;
    use sui::tx_context::{TxContext, sender};
    use sui::object;
    use sui::table;
    use sui::transfer;
    use std::type_name::{get, into_string};
    use std::ascii::{into_bytes};
    use std::string;
    use owlswap_amm::pool::{Self, Pool};
    use owlswap_amm::events;
    use sui::coin;

    friend owlswap_amm::router;

    const E_NOT_AUTHORIZED : u64 = 201;

    struct Control has key {
        id: UID,
        owner: address,
        pools: Table<String, ID>,
        count: u64,
    }

    fun init(ctx: &mut TxContext) {
        let store = Control{
            id: object::new(ctx),
            owner: sender(ctx),
            pools: table::new<String, ID>(ctx),
            count: 0,
        };
        transfer::share_object(store);
    }

    public entry fun withdraw<X, Y>(control: &mut Control, pool: &mut Pool<X, Y>, recipient: address, ctx: &mut TxContext) {
        check_owner(control, ctx);
        let (x_coin, y_coin) = pool::withdraw_foundation_fee(pool, ctx);

        if(recipient == @zero) {
            recipient = sender(ctx);
        };

        let x_value = coin::value(&x_coin);
        let y_value = coin::value(&y_coin);

        transfer::transfer(x_coin, recipient);
        transfer::transfer(y_coin, recipient);

        events::emit_fundation_fee_withdraw(id(pool), x_value, y_value, recipient);
    }

    public entry fun withdraw_all() {

    }

    public(friend) fun add<X, Y>(control: &mut Control, id: ID) : String{
        let lp_name = get_name_x_y<X, Y>();
        table::add(&mut control.pools, lp_name, id);
        control.count = control.count + 1;
        lp_name
    }

    public(friend) fun exist<X, Y>(control: &mut Control) : bool {
        table::contains(&mut control.pools, get_name_x_y<X, Y>())
    }

    public fun get_name_x_y<X, Y>() : String {
        let name_x = get_name<X>();
        let name_y = get_name<Y>();
        string::append_utf8(&mut name_x, b"-");
        string::append(&mut name_x, name_y);
        name_x
    }

    public fun get_name<Coin>() : String {
        let name = get<Coin>();
        let str = string::utf8(b"");
        string::append_utf8(&mut str, into_bytes(into_string(name)));
        str
    }

    fun check_owner(control: &mut Control, ctx: &mut TxContext) {
        assert!(control.owner == sender(ctx), E_NOT_AUTHORIZED);
    }

}