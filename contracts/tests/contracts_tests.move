#[test_only]
module contracts::lpcontrol_tests;

use contracts::lpcontrol::{
    Self,
    LPPool,
    E_INVALID_AMOUNT,
    E_NOT_ADMIN,
    E_POOL_PAUSED,
    E_INSUFFICIENT_AVAILABLE_BALANCE,
    E_INSUFFICIENT_RESERVE,
    E_NOT_AUTHORIZED_SUBMITTER,
    E_NOT_AUTHORIZED_LIQUIDATOR,
    E_INSUFFICIENT_USER_BALANCE,
    E_USER_NOT_FOUND
};
use sui::balance;
use sui::coin::{Self, Coin};
use sui::event;
use sui::object::{Self, UID};
use sui::sui::SUI;
use sui::test_scenario::{Self as test, Scenario};
use sui::tx_context::{Self as tx_context, TxContext};

// === Test Constants ===
const ADMIN: address = @0xA;
const USER1: address = @0xB;
const USER2: address = @0xC;
const SUBMITTER: address = @0xD;
const LIQUIDATOR: address = @0xE;
const LP_INITIAL_DEPOSIT: u64 = 1_000_000_000; // 1000 SUI
const USER_INITIAL_DEPOSIT: u64 = 100_000_000; // 100 SUI
const MIN_RESERVE_RATIO: u64 = 1000; // 10%

// === Helper Functions ===

// Helper to create and initialize the LPPool
fun create_lp_pool(scenario: &mut Scenario): LPPool<SUI> {
    test::next_tx(scenario, ADMIN);
    let ctx = test::ctx(scenario);
    let mut pool = contracts::init(ctx);

    // Set admin and authorized roles
    contracts::set_admin(&mut pool, ADMIN, &mut ctx);
    contracts::add_authorized_submitter(&mut pool, SUBMITTER, &mut ctx);
    contracts::add_authorized_liquidator(&mut pool, LIQUIDATOR, &mut ctx);
    contracts::set_min_reserve_ratio(&mut pool, MIN_RESERVE_RATIO, &mut ctx);

    pool
}

// Helper to mint SUI and deposit into an address
fun mint_and_deposit_sui(scenario: &mut Scenario, recipient: address, amount: u64): Coin<SUI> {
    test::next_tx(scenario, recipient);
    let ctx = test::ctx(scenario);
    coin::mint_for_testing<SUI>(amount, ctx)
}

// === Test Cases ===

#[test]
fun test_init() {
    let scenario = test::begin(ADMIN);
    let ctx = test::ctx(&mut scenario);

    let pool = contracts::init(ctx);

    // Assert initial state
    assert!(pool.treasury.value() == 0, 0);
    assert!(pool.available_balance == 0, 0);
    assert!(pool.reserved_balance == 0, 0);
    assert!(pool.user_treasury.value() == 0, 0);
    assert!(pool.total_user_deposits == 0, 0);
    assert!(pool.admin == ADMIN, 0);
    assert!(pool.paused == false, 0);
    assert!(pool.min_reserve_ratio == 0, 0); // Default value from init
    assert!(pool.authorized_submitters.length() == 0, 0);
    assert!(pool.authorized_liquidators.length() == 0, 0);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_deposit_liquidity() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // USER1 deposits liquidity
    let deposit_amount = LP_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);

    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    // Verify pool state
    assert!(pool.treasury.value() == deposit_amount, 0);
    assert!(pool.available_balance == deposit_amount, 0);
    assert!(pool.total_lp_deposits == deposit_amount, 0);
    assert!(pool.reserved_balance == 0, 0);

    // Verify event emitted
    test::assert_event(
        &mut scenario,
        LiquidityDepositedEvent {
            depositor: USER1,
            amount: deposit_amount,
            total_available: deposit_amount,
        },
    );

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_INVALID_AMOUNT)]
fun test_deposit_liquidity_invalid_amount() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    let coins = mint_and_deposit_sui(&mut scenario, USER1, 0); // Deposit 0 amount

    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_withdraw_liquidity_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // Deposit initial liquidity
    let deposit_amount = LP_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    // Admin withdraws liquidity
    let withdraw_amount = 500_000_000; // 500 SUI
    test::next_tx(&mut scenario, ADMIN);
    let ctx = test::ctx(&mut scenario);
    contracts::withdraw_liquidity(&mut pool, USER2, withdraw_amount, &mut ctx);

    // Verify pool state
    assert!(pool.treasury.value() == deposit_amount - withdraw_amount, 0);
    assert!(pool.available_balance == deposit_amount - withdraw_amount, 0);
    assert!(pool.total_lp_deposits == deposit_amount, 0); // Total LP deposits should not change on withdrawal

    // Verify recipient balance
    test::next_tx(&mut scenario, USER2);
    let user2_balance = test::balance_of<SUI>(&mut scenario, USER2);
    assert!(user2_balance == withdraw_amount, 0);

    // Verify event emitted
    test::assert_event(
        &mut scenario,
        LiquidityWithdrawnEvent {
            admin: ADMIN,
            to: USER2,
            amount: withdraw_amount,
            remaining_available: deposit_amount - withdraw_amount,
        },
    );

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_NOT_ADMIN)]
fun test_withdraw_liquidity_not_admin() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // Deposit initial liquidity
    let deposit_amount = LP_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    // USER1 tries to withdraw (not admin)
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::withdraw_liquidity(&mut pool, USER1, 100_000_000, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_INSUFFICIENT_AVAILABLE_BALANCE)]
fun test_withdraw_liquidity_insufficient_available() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // Deposit initial liquidity
    let deposit_amount = LP_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    // Admin tries to withdraw more than available
    test::next_tx(&mut scenario, ADMIN);
    let ctx = test::ctx(&mut scenario);
    contracts::withdraw_liquidity(&mut pool, USER2, deposit_amount + 1, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_INSUFFICIENT_RESERVE)]
fun test_withdraw_liquidity_breaks_reserve_ratio() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // Deposit initial liquidity
    let deposit_amount = LP_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    // Reserve some funds
    let reserved_amount = 100_000_000; // 100 SUI
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx_submitter = test::ctx(&mut scenario);
    contracts::reserve_funds(
        &mut pool,
        object::new(ctx_submitter),
        reserved_amount,
        &mut ctx_submitter,
    );

    // Admin tries to withdraw almost all available, breaking the min_reserve_ratio
    // available_balance = deposit_amount - reserved_amount
    // min_required = reserved_amount * 1.1 (10% ratio)
    // remaining_balance = available_balance - withdraw_amount
    // We need remaining_balance >= min_required
    // (deposit_amount - reserved_amount) - withdraw_amount < reserved_amount * (10000 + MIN_RESERVE_RATIO) / 10000
    // (1_000_000_000 - 100_000_000) - withdraw_amount < 100_000_000 * 1.1
    // 900_000_000 - withdraw_amount < 110_000_000
    // withdraw_amount > 790_000_000

    let withdraw_amount_too_much =
        (deposit_amount - reserved_amount) - (reserved_amount * (10000 + MIN_RESERVE_RATIO) / 10000) + 1;

    test::next_tx(&mut scenario, ADMIN);
    let ctx_admin = test::ctx(&mut scenario);
    contracts::withdraw_liquidity(&mut pool, USER2, withdraw_amount_too_much, &mut ctx_admin);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_user_deposit_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // User1 deposits
    let deposit_amount = USER_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_deposit(&mut pool, coins, &mut ctx);

    // Verify pool state
    assert!(pool.user_treasury.value() == deposit_amount, 0);
    assert!(pool.total_user_deposits == deposit_amount, 0);
    assert!(*pool.user_balances.borrow(USER1) == deposit_amount, 0);

    // Verify event
    test::assert_event(
        &mut scenario,
        UserDepositedEvent {
            user: USER1,
            amount: deposit_amount,
            new_balance: deposit_amount,
        },
    );

    // User1 deposits again
    let second_deposit_amount = 50_000_000;
    let second_coins = mint_and_deposit_sui(&mut scenario, USER1, second_deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_deposit(&mut pool, second_coins, &mut ctx);

    // Verify updated state
    assert!(pool.user_treasury.value() == deposit_amount + second_deposit_amount, 0);
    assert!(pool.total_user_deposits == deposit_amount + second_deposit_amount, 0);
    assert!(*pool.user_balances.borrow(USER1) == deposit_amount + second_deposit_amount, 0);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_INVALID_AMOUNT)]
fun test_user_deposit_invalid_amount() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    let coins = mint_and_deposit_sui(&mut scenario, USER1, 0);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_deposit(&mut pool, coins, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_user_withdraw_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // User1 deposits
    let deposit_amount = USER_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_deposit(&mut pool, coins, &mut ctx);

    // User1 withdraws
    let withdraw_amount = 50_000_000;
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_withdraw(&mut pool, withdraw_amount, &mut ctx);

    // Verify pool state
    assert!(pool.user_treasury.value() == deposit_amount - withdraw_amount, 0);
    assert!(pool.total_user_deposits == deposit_amount - withdraw_amount, 0);
    assert!(*pool.user_balances.borrow(USER1) == deposit_amount - withdraw_amount, 0);

    // Verify user balance
    test::next_tx(&mut scenario, USER1);
    let user1_balance = test::balance_of<SUI>(&mut scenario, USER1);
    assert!(user1_balance == withdraw_amount, 0);

    // Verify event
    test::assert_event(
        &mut scenario,
        UserWithdrewnEvent {
            user: USER1,
            amount: withdraw_amount,
            remaining_balance: deposit_amount - withdraw_amount,
        },
    );

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_USER_NOT_FOUND)]
fun test_user_withdraw_user_not_found() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // USER1 tries to withdraw without depositing
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_withdraw(&mut pool, 10_000_000, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_INSUFFICIENT_USER_BALANCE)]
fun test_user_withdraw_insufficient_balance() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // User1 deposits a small amount
    let deposit_amount = 10_000_000;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_deposit(&mut pool, coins, &mut ctx);

    // User1 tries to withdraw more than deposited
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_withdraw(&mut pool, deposit_amount + 1, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_reserve_funds_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // Deposit initial liquidity
    let deposit_amount = LP_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    // Submitter reserves funds
    let reserve_amount = 200_000_000;
    let option_id = object::new(test::ctx(&mut scenario));
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx = test::ctx(&mut scenario);
    let result = contracts::reserve_funds(&mut pool, option_id, reserve_amount, &mut ctx);

    assert!(result, 0);
    assert!(pool.available_balance == deposit_amount - reserve_amount, 0);
    assert!(pool.reserved_balance == reserve_amount, 0);

    test::assert_event(
        &mut scenario,
        FundsReservedEvent {
            option_id: option_id,
            amount: reserve_amount,
            remaining_available: deposit_amount - reserve_amount,
            total_reserved: reserve_amount,
        },
    );

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_NOT_AUTHORIZED_SUBMITTER)]
fun test_reserve_funds_not_authorized() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // Deposit initial liquidity
    let deposit_amount = LP_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    // USER1 tries to reserve funds (not authorized)
    let option_id = object::new(test::ctx(&mut scenario));
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::reserve_funds(&mut pool, option_id, 100_000_000, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_reserve_funds_insufficient_available_returns_false() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // Deposit initial liquidity
    let deposit_amount = 100_000_000;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    // Submitter tries to reserve more than available
    let option_id = object::new(test::ctx(&mut scenario));
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx = test::ctx(&mut scenario);
    let result = contracts::reserve_funds(&mut pool, option_id, deposit_amount + 1, &mut ctx);

    assert!(!result, 0);
    assert!(pool.available_balance == deposit_amount, 0); // No change
    assert!(pool.reserved_balance == 0, 0); // No change

    // No event should be emitted
    test::assert_no_events(&mut scenario);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_collect_premium_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // User1 deposits
    let user_deposit_amount = USER_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, user_deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_deposit(&mut pool, coins, &mut ctx);

    // LP deposits liquidity
    let lp_deposit_amount = LP_INITIAL_DEPOSIT;
    let lp_coins = mint_and_deposit_sui(&mut scenario, USER2, lp_deposit_amount); // Different user for LP to avoid confusion
    test::next_tx(&mut scenario, USER2);
    let ctx_lp = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, lp_coins, &mut ctx_lp);

    // Submitter collects premium from User1
    let premium_amount = 10_000_000;
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx_submitter = test::ctx(&mut scenario);
    contracts::collect_premium(&mut pool, USER1, premium_amount, &mut ctx_submitter);

    // Verify pool state
    assert!(pool.user_treasury.value() == user_deposit_amount - premium_amount, 0);
    assert!(pool.total_user_deposits == user_deposit_amount - premium_amount, 0);
    assert!(*pool.user_balances.borrow(USER1) == user_deposit_amount - premium_amount, 0);
    assert!(pool.treasury.value() == lp_deposit_amount + premium_amount, 0);
    assert!(pool.available_balance == lp_deposit_amount + premium_amount, 0);

    // Verify event
    test::assert_event(
        &mut scenario,
        PremiumCollectedEvent {
            user: USER1,
            amount: premium_amount,
            user_remaining_balance: user_deposit_amount - premium_amount,
            total_available: lp_deposit_amount + premium_amount,
        },
    );

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_NOT_AUTHORIZED_SUBMITTER)]
fun test_collect_premium_not_authorized() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // User1 deposits
    let user_deposit_amount = USER_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, user_deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_deposit(&mut pool, coins, &mut ctx);

    // USER2 tries to collect premium (not authorized)
    test::next_tx(&mut scenario, USER2);
    let ctx = test::ctx(&mut scenario);
    contracts::collect_premium(&mut pool, USER1, 10_000_000, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_USER_NOT_FOUND)]
fun test_collect_premium_user_not_found() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // Submitter tries to collect premium from non-existent user
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx = test::ctx(&mut scenario);
    contracts::collect_premium(&mut pool, USER1, 10_000_000, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_INSUFFICIENT_USER_BALANCE)]
fun test_collect_premium_insufficient_user_balance() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // User1 deposits a small amount
    let user_deposit_amount = 5_000_000;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, user_deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_deposit(&mut pool, coins, &mut ctx);

    // Submitter tries to collect more premium than user has
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx = test::ctx(&mut scenario);
    contracts::collect_premium(&mut pool, USER1, user_deposit_amount + 1, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_pay_user_profit_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // LP deposits liquidity
    let lp_deposit_amount = LP_INITIAL_DEPOSIT;
    let lp_coins = mint_and_deposit_sui(&mut scenario, USER1, lp_deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx_lp = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, lp_coins, &mut ctx_lp);

    // Reserve some funds for an option
    let option_payout = 200_000_000;
    let option_id = object::new(test::ctx(&mut scenario));
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx_submitter = test::ctx(&mut scenario);
    contracts::reserve_funds(&mut pool, option_id, option_payout, &mut ctx_submitter);

    // Liquidator pays profit to User2
    let profit_amount = 150_000_000;
    test::next_tx(&mut scenario, LIQUIDATOR);
    let ctx_liquidator = test::ctx(&mut scenario);
    contracts::pay_user_profit(&mut pool, USER2, profit_amount, &mut ctx_liquidator);

    // Verify pool state
    assert!(pool.reserved_balance == option_payout - profit_amount, 0);
    assert!(pool.user_treasury.value() == profit_amount, 0);
    assert!(pool.total_user_deposits == profit_amount, 0);
    assert!(*pool.user_balances.borrow(USER2) == profit_amount, 0);

    // Verify event
    test::assert_event(
        &mut scenario,
        UserProfitPaidEvent {
            user: USER2,
            amount: profit_amount,
            new_user_balance: profit_amount,
        },
    );

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_NOT_AUTHORIZED_LIQUIDATOR)]
fun test_pay_user_profit_not_authorized() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // LP deposits liquidity
    let lp_deposit_amount = LP_INITIAL_DEPOSIT;
    let lp_coins = mint_and_deposit_sui(&mut scenario, USER1, lp_deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx_lp = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, lp_coins, &mut ctx_lp);

    // Reserve some funds for an option
    let option_payout = 200_000_000;
    let option_id = object::new(test::ctx(&mut scenario));
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx_submitter = test::ctx(&mut scenario);
    contracts::reserve_funds(&mut pool, option_id, option_payout, &mut ctx_submitter);

    // USER1 tries to pay profit (not authorized)
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::pay_user_profit(&mut pool, USER2, 10_000_000, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_INSUFFICIENT_RESERVE)]
fun test_pay_user_profit_insufficient_reserved() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // LP deposits liquidity
    let lp_deposit_amount = LP_INITIAL_DEPOSIT;
    let lp_coins = mint_and_deposit_sui(&mut scenario, USER1, lp_deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx_lp = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, lp_coins, &mut ctx_lp);

    // Reserve a small amount
    let option_payout = 10_000_000;
    let option_id = object::new(test::ctx(&mut scenario));
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx_submitter = test::ctx(&mut scenario);
    contracts::reserve_funds(&mut pool, option_id, option_payout, &mut ctx_submitter);

    // Liquidator tries to pay more profit than reserved
    test::next_tx(&mut scenario, LIQUIDATOR);
    let ctx = test::ctx(&mut scenario);
    contracts::pay_user_profit(&mut pool, USER2, option_payout + 1, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_release_reserved_funds_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // LP deposits liquidity
    let deposit_amount = LP_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    // Reserve some funds
    let reserve_amount = 200_000_000;
    let option_id = object::new(test::ctx(&mut scenario));
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx_submitter = test::ctx(&mut scenario);
    contracts::reserve_funds(&mut pool, option_id, reserve_amount, &mut ctx_submitter);

    // Liquidator releases reserved funds
    test::next_tx(&mut scenario, LIQUIDATOR);
    let ctx_liquidator = test::ctx(&mut scenario);
    contracts::release_reserved_funds(&mut pool, reserve_amount, &mut ctx_liquidator);

    // Verify pool state
    assert!(pool.reserved_balance == 0, 0);
    assert!(pool.available_balance == deposit_amount, 0); // Should be back to initial deposit amount

    // No specific event for release_reserved_funds, but previous events are still there.
    // We can assert the state directly.

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_NOT_AUTHORIZED_LIQUIDATOR)]
fun test_release_reserved_funds_not_authorized() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // LP deposits liquidity
    let deposit_amount = LP_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    // Reserve some funds
    let reserve_amount = 200_000_000;
    let option_id = object::new(test::ctx(&mut scenario));
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx_submitter = test::ctx(&mut scenario);
    contracts::reserve_funds(&mut pool, option_id, reserve_amount, &mut ctx_submitter);

    // USER1 tries to release funds (not authorized)
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::release_reserved_funds(&mut pool, reserve_amount, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_INSUFFICIENT_RESERVE)]
fun test_release_reserved_funds_insufficient_reserved() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // Liquidator tries to release more funds than reserved (0 in this case)
    test::next_tx(&mut scenario, LIQUIDATOR);
    let ctx = test::ctx(&mut scenario);
    contracts::release_reserved_funds(&mut pool, 1, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_get_pool_status() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    let (
        treasury_val,
        available_val,
        reserved_val,
        user_treasury_val,
        total_user_deposits_val,
    ) = contracts::get_pool_status(&pool);
    assert!(treasury_val == 0, 0);
    assert!(available_val == 0, 0);
    assert!(reserved_val == 0, 0);
    assert!(user_treasury_val == 0, 0);
    assert!(total_user_deposits_val == 0, 0);

    // Deposit liquidity
    let lp_deposit_amount = LP_INITIAL_DEPOSIT;
    let lp_coins = mint_and_deposit_sui(&mut scenario, USER1, lp_deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, lp_coins, &mut ctx);

    // User deposit
    let user_deposit_amount = USER_INITIAL_DEPOSIT;
    let user_coins = mint_and_deposit_sui(&mut scenario, USER2, user_deposit_amount);
    test::next_tx(&mut scenario, USER2);
    let ctx = test::ctx(&mut scenario);
    contracts::user_deposit(&mut pool, user_coins, &mut ctx);

    // Reserve funds
    let reserve_amount = 200_000_000;
    let option_id = object::new(test::ctx(&mut scenario));
    test::next_tx(&mut scenario, SUBMITTER);
    let ctx_submitter = test::ctx(&mut scenario);
    contracts::reserve_funds(&mut pool, option_id, reserve_amount, &mut ctx_submitter);

    let (
        treasury_val,
        available_val,
        reserved_val,
        user_treasury_val,
        total_user_deposits_val,
    ) = contracts::get_pool_status(&pool);
    assert!(treasury_val == lp_deposit_amount, 0);
    assert!(available_val == lp_deposit_amount - reserve_amount, 0);
    assert!(reserved_val == reserve_amount, 0);
    assert!(user_treasury_val == user_deposit_amount, 0);
    assert!(total_user_deposits_val == user_deposit_amount, 0);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_get_user_balance() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // User has no balance initially
    assert!(contracts::get_user_balance(&pool, USER1) == 0, 0);

    // User1 deposits
    let deposit_amount = USER_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_deposit(&mut pool, coins, &mut ctx);

    assert!(contracts::get_user_balance(&pool, USER1) == deposit_amount, 0);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_can_reserve_funds() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // Initially no available balance
    assert!(!contracts::can_reserve_funds(&pool, 1), 0);

    // Deposit liquidity
    let deposit_amount = LP_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::deposit_liquidity(&mut pool, coins, &mut ctx);

    assert!(contracts::can_reserve_funds(&pool, 100_000_000), 0);
    assert!(!contracts::can_reserve_funds(&pool, deposit_amount + 1), 0);

    test::next_tx(&mut scenario, ADMIN);
    let ctx_admin = test::ctx(&mut scenario);
    contracts::toggle_pause(&mut pool, true, &mut ctx_admin);
    assert!(!contracts::can_reserve_funds(&pool, 100_000_000), 0); // Paused, so cannot reserve

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_can_pay_premium() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    // User has no balance initially
    assert!(!contracts::can_pay_premium(&pool, USER1, 1), 0);

    // User1 deposits
    let deposit_amount = USER_INITIAL_DEPOSIT;
    let coins = mint_and_deposit_sui(&mut scenario, USER1, deposit_amount);
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::user_deposit(&mut pool, coins, &mut ctx);

    assert!(contracts::can_pay_premium(&pool, USER1, 50_000_000), 0);
    assert!(!contracts::can_pay_premium(&pool, USER1, deposit_amount + 1), 0);
    assert!(!contracts::can_pay_premium(&pool, USER2, 1), 0); // User2 has no balance

    test::return_shared(pool);
    test::end(scenario);
}

// === Permission management functions ===

#[test]
fun test_set_admin_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    let NEW_ADMIN: address = @0xF;
    test::next_tx(&mut scenario, ADMIN); // Current admin
    let ctx = test::ctx(&mut scenario);
    contracts::set_admin(&mut pool, NEW_ADMIN, &mut ctx);

    assert!(pool.admin == NEW_ADMIN, 0);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_NOT_ADMIN)]
fun test_set_admin_not_admin() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    let NEW_ADMIN: address = @0xF;
    test::next_tx(&mut scenario, USER1); // Not admin
    let ctx = test::ctx(&mut scenario);
    contracts::set_admin(&mut pool, NEW_ADMIN, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_add_authorized_submitter_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    let NEW_SUBMITTER: address = @0xF;
    test::next_tx(&mut scenario, ADMIN);
    let ctx = test::ctx(&mut scenario);
    contracts::add_authorized_submitter(&mut pool, NEW_SUBMITTER, &mut ctx);

    assert!(pool.authorized_submitters.contains(&NEW_SUBMITTER), 0);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_NOT_ADMIN)]
fun test_add_authorized_submitter_not_admin() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    let NEW_SUBMITTER: address = @0xF;
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::add_authorized_submitter(&mut pool, NEW_SUBMITTER, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_remove_authorized_submitter_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    assert!(pool.authorized_submitters.contains(&SUBMITTER), 0); // Added in create_lp_pool

    test::next_tx(&mut scenario, ADMIN);
    let ctx = test::ctx(&mut scenario);
    contracts::remove_authorized_submitter(&mut pool, SUBMITTER, &mut ctx);

    assert!(!pool.authorized_submitters.contains(&SUBMITTER), 0);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_NOT_ADMIN)]
fun test_remove_authorized_submitter_not_admin() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::remove_authorized_submitter(&mut pool, SUBMITTER, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_add_authorized_liquidator_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    let NEW_LIQUIDATOR: address = @0xF;
    test::next_tx(&mut scenario, ADMIN);
    let ctx = test::ctx(&mut scenario);
    contracts::add_authorized_liquidator(&mut pool, NEW_LIQUIDATOR, &mut ctx);

    assert!(pool.authorized_liquidators.contains(&NEW_LIQUIDATOR), 0);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_NOT_ADMIN)]
fun test_add_authorized_liquidator_not_admin() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    let NEW_LIQUIDATOR: address = @0xF;
    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::add_authorized_liquidator(&mut pool, NEW_LIQUIDATOR, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_remove_authorized_liquidator_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    assert!(pool.authorized_liquidators.contains(&LIQUIDATOR), 0); // Added in create_lp_pool

    test::next_tx(&mut scenario, ADMIN);
    let ctx = test::ctx(&mut scenario);
    contracts::remove_authorized_liquidator(&mut pool, LIQUIDATOR, &mut ctx);

    assert!(!pool.authorized_liquidators.contains(&LIQUIDATOR), 0);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_NOT_ADMIN)]
fun test_remove_authorized_liquidator_not_admin() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::remove_authorized_liquidator(&mut pool, LIQUIDATOR, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_toggle_pause_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    assert!(pool.paused == false, 0);

    test::next_tx(&mut scenario, ADMIN);
    let ctx = test::ctx(&mut scenario);
    contracts::toggle_pause(&mut pool, true, &mut ctx);
    assert!(pool.paused == true, 0);

    test::next_tx(&mut scenario, ADMIN);
    let ctx = test::ctx(&mut scenario);
    contracts::toggle_pause(&mut pool, false, &mut ctx);
    assert!(pool.paused == false, 0);

    test::return_shared(pool);
    test::end(scenario);
}

#[test, expected_failure(abort_code = contracts::E_NOT_ADMIN)]
fun test_toggle_pause_not_admin() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    test::next_tx(&mut scenario, USER1);
    let ctx = test::ctx(&mut scenario);
    contracts::toggle_pause(&mut pool, true, &mut ctx);

    test::return_shared(pool);
    test::end(scenario);
}

#[test]
fun test_set_min_reserve_ratio_success() {
    let scenario = test::begin(ADMIN);
    let mut pool = create_lp_pool(&mut scenario);

    assert!(pool.min_reserve_ratio == MIN_RESERVE_RATIO, 0);

    let NEW_RATIO = 2000;
    test::next_tx(&mut scenario, ADMIN);
    let ctx = test::ctx(&mut scenario);
    contracts::set_min_reserve_ratio(&mut pool, NEW_RATIO, &mut ctx);
    assert!(pool.min_reserve_ratio == NEW_RATIO, 0);

    test::return_shared(pool);
    test::end(scenario);
}

// #[test, expected_failure(abort_code = contracts::E_NOT_ADMIN)]
// fun test_set_min_reserve_ratio_not_admin() {
//     let scenario = test::begin(ADMIN);
//     let mut pool = create_lp_pool(&mut scenario);

//     test::next_tx(&mut scenario, USER1);
//     let ctx = test::ctx(&mut scenario);
//     contracts::set_min_reserve_ratio(&mut pool, 1000, &mut ctx);

//     test::return_shared(pool);
//     test::end(scenario);
// }
