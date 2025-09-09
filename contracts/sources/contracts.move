module contracts::lpcontrol;

use std::string::{Self, String};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event::{Self, emit};
use sui::sui::SUI;
use sui::table::{Self, Table};

const E_POOL_PAUSED: u64 = 0;
const E_INVALID_AMOUNT: u64 = 1;
const E_NOT_ADMIN: u64 = 2;
const E_INSUFFICIENT_AVAILABLE_BALANCE: u64 = 3;
const E_INSUFFICIENT_RESERVE: u64 = 4;
const E_NOT_AUTHORIZED_SUBMITTER: u64 = 5;
const E_NOT_AUTHORIZED_LIQUIDATOR: u64 = 6;
const E_NOT_AUTHORIZED_ADMIN: u64 = 7;
const E_INSUFFICIENT_USER_BALANCE: u64 = 8;
const E_USER_NOT_FOUND: u64 = 9;
const E_AUTHORIZED_SUBMITTER_ALREADY_EXISTS: u64 = 10;
const E_AUTHORIZED_LIQUIDATOR_ALREADY_EXISTS: u64 = 11;

// === 事件定义 ===
public struct AuthControlCreatedEvent has copy, drop {
    admin: address,
    authorized_submitters: vector<address>,
    authorized_liquidators: vector<address>,
}

public struct LPPoolinitCreatedEvent has copy, drop {
    creator: address,
    sui_create: string::String,
}

public struct LPPoolCreatedEvent has copy, drop {
    creator: address,
    treasury_type: string::String,
}

public struct LiquidityDepositedEvent has copy, drop {
    depositor: address,
    amount: u64,
    total_available: u64,
}

public struct LiquidityWithdrawnEvent has copy, drop {
    admin: address,
    to: address,
    amount: u64,
    remaining_available: u64,
}

public struct FundsReservedEvent has copy, drop {
    option_id: u64,
    amount: u64,
    remaining_available: u64,
    total_reserved: u64,
}

public struct PremiumCollectedEvent has copy, drop {
    user: address,
    amount: u64,
    user_remaining_balance: u64,
    total_available: u64,
}

public struct UserDepositedEvent has copy, drop {
    user: address,
    amount: u64,
    new_balance: u64,
}

public struct UserWithdrewnEvent has copy, drop {
    user: address,
    amount: u64,
    remaining_balance: u64,
}

public struct UserProfitPaidEvent has copy, drop {
    user: address,
    amount: u64,
    new_user_balance: u64,
}

public struct UserOrderSubmittedEvent has copy, drop {
    order_id: String,
    user_addr: address,
    premium_amount: u64,
    option_id: u64,
    potential_payout: u64,
}

public struct OrderLiquidatedEvent has copy, drop {
        option_id:u64,
        user_addr:address,
        liquidator: address,
        reserved_released_amount: u64,
        payout_to_user_amount: u64,
        new_available_balance: u64,
        new_reserved_balance: u64,
}

public struct AuthorizedSubmitterAddedEvent has copy, drop {
    submitter_addr: address,
}

public struct AuthorizedLiquidatorAddedEvent has copy, drop {
    liquidator_addr: address,
}

public struct AdminAddedEvent has copy, drop {
    admin_addr: address,
}

// === 主要结构体 ===

// 权限控制：指定admin和授权的提交者和清算者
public struct AuthControl has key {
    id: UID,
    admin: vector<address>,
}

// 简化的 LP 资金池
public struct LPPool<phantom T> has key {
    id: UID,
    // === 核心资金管理（平台资金） ===
    treasury: Balance<T>, // 平台总资金
    available_balance: u64, // 平台可用资金（未被期权占用）
    reserved_balance: u64, // 平台预留资金（被期权占用）
    // === 用户资金管理（用户存款，与平台资金分开） ===
    user_treasury: Balance<T>, // 用户存款总资金
    user_balances: Table<address, u64>, // 用户余额记录
    // === LP 管理 ===
    // === 权限控制 ===
    admin: address, // 管理员地址
    authorized_submitters: vector<address>, // 授权的订单提交者
    authorized_liquidators: vector<address>, // 授权的清算者
    // === 基础配置 ===
    paused: bool, // 紧急暂停开关
    min_reserve_ratio: u64, // 最小预留比例（防止资金全部被占用）
}

fun init(ctx: &mut TxContext) {
    let mut auth_control = AuthControl {
        id: object::new(ctx),
        admin: vector::empty<address>(),
    };
    vector::push_back(&mut auth_control.admin, ctx.sender());

    let mut pool = LPPool<SUI> {
        id: object::new(ctx),
        treasury: balance::zero<SUI>(),
        available_balance: 0,
        reserved_balance: 0,
        user_treasury: balance::zero<SUI>(),
        user_balances: table::new(ctx),
        admin: ctx.sender(),
        authorized_submitters: vector::empty<address>(),
        authorized_liquidators: vector::empty<address>(),
        paused: false,
        min_reserve_ratio: 20,
    };

    vector::push_back(&mut pool.authorized_liquidators, ctx.sender());
    vector::push_back(&mut pool.authorized_submitters, ctx.sender());

    event::emit(LPPoolinitCreatedEvent {
        creator: ctx.sender(),
        sui_create: string::utf8(b"SUI"),
    });

    event::emit(AuthControlCreatedEvent {
        admin: ctx.sender(),
        authorized_submitters: vector::empty<address>(),
        authorized_liquidators: vector::empty<address>(),
    });

    transfer::share_object(pool);
    transfer::share_object(auth_control);
}
// === LP 特权地址管理===

// 1. 添加订单提交者
entry fun add_authorized_submitter<T>(
    pool: &mut LPPool<T>,
    submitter_addr: address,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == pool.admin, E_NOT_ADMIN);
    assert!(
        !pool.authorized_submitters.contains(&submitter_addr),
        E_AUTHORIZED_SUBMITTER_ALREADY_EXISTS,
    );
    vector::push_back(&mut pool.authorized_submitters, submitter_addr);

    event::emit(AuthorizedSubmitterAddedEvent {
        submitter_addr,
    });
}

// 2. 添加清算者
entry fun add_authorized_liquidator<T>(
    pool: &mut LPPool<T>,
    liquidator_addr: address,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == pool.admin, E_NOT_ADMIN);
    assert!(
        !pool.authorized_liquidators.contains(&liquidator_addr),
        E_AUTHORIZED_LIQUIDATOR_ALREADY_EXISTS,
    );
    vector::push_back(&mut pool.authorized_liquidators, liquidator_addr);

    event::emit(AuthorizedLiquidatorAddedEvent {
        liquidator_addr,
    });
}

// 3. 添加管理员
entry fun add_admin(auth_control: &mut AuthControl, new_admin_addr: address, ctx: &TxContext) {
    assert!(auth_control.admin.contains(&ctx.sender()), E_NOT_ADMIN);
    vector::push_back(&mut auth_control.admin, new_admin_addr);
    emit(AdminAddedEvent {
        admin_addr: new_admin_addr,
    });
}

// === LP流动性管理功能 ===

// 1. LP 存入流动性（平台方资金）
entry fun deposit_liquidity<T>(pool: &mut LPPool<T>, coins: Coin<T>, ctx: &TxContext) {
    let depositor_addr = ctx.sender();
    let deposit_amount = coins.value();

    // 基础检查
    assert!(!pool.paused, E_POOL_PAUSED);
    assert!(coins.value() > 0, E_INVALID_AMOUNT);

    // 更新平台资金
    coin::put(&mut pool.treasury, coins);
    pool.available_balance = pool.available_balance + deposit_amount;

    // 发射事件
    event::emit(LiquidityDepositedEvent {
        depositor: depositor_addr,
        amount: deposit_amount,
        total_available: pool.available_balance,
    });
}

// 2. LP 提取流动性（仅管理员可执行，从平台资金中提取）
entry fun withdraw_liquidity<T>(
    pool: &mut LPPool<T>,
    to: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    // 权限检查
    assert!(ctx.sender() == pool.admin, E_NOT_ADMIN);
    assert!(!pool.paused, E_POOL_PAUSED);
    assert!(amount > 0, E_INVALID_AMOUNT);

    // 流动性检查 - 确保不影响期权赔付
    assert!(pool.available_balance >= amount, E_INSUFFICIENT_AVAILABLE_BALANCE);

    // 最小预留检查 - 防止池子被完全掏空
    let total_balance = pool.treasury.value();
    let remaining_balance = total_balance - amount;
    let min_required = pool.reserved_balance * pool.min_reserve_ratio/100;
    assert!(remaining_balance >= min_required, E_INSUFFICIENT_RESERVE);

    // 执行提取
    let withdraw_coin = coin::take(&mut pool.treasury, amount, ctx);
    transfer::public_transfer(withdraw_coin, to);
    pool.available_balance = pool.available_balance - amount;

    // 发射事件
    event::emit(LiquidityWithdrawnEvent {
        admin: ctx.sender(),
        to,
        amount,
        remaining_available: pool.available_balance,
    });
}

// === 用户资金管理功能 ===

// 3. 用户存入资金
entry fun user_deposit<T>(pool: &mut LPPool<T>, coins: Coin<T>, ctx: &TxContext) {
    let user_addr = ctx.sender();
    let deposit_amount = coins.value();

    // 基础检查
    assert!(!pool.paused, E_POOL_PAUSED);
    assert!(coins.value() > 0, E_INVALID_AMOUNT);

    // 更新用户资金
    coin::put(&mut pool.user_treasury, coins);

    // 更新用户余额
    if (pool.user_balances.contains(user_addr)) {
        let current_balance = pool.user_balances.borrow_mut(user_addr);
        *current_balance = *current_balance + deposit_amount;
    } else {
        pool.user_balances.add(user_addr, deposit_amount);
    };

    let new_balance = *pool.user_balances.borrow(user_addr);

    // 发射事件
    event::emit(UserDepositedEvent {
        user: user_addr,
        amount: deposit_amount,
        new_balance,
    });
}

// 4. 用户提取资金
entry fun user_withdraw<T>(pool: &mut LPPool<T>, amount: u64, ctx: &mut TxContext) {
    let user_addr = ctx.sender();

    // 基础检查
    assert!(!pool.paused, E_POOL_PAUSED);
    assert!(amount > 0, E_INVALID_AMOUNT);
    assert!(pool.user_balances.contains(user_addr), E_USER_NOT_FOUND);

    let current_balance = pool.user_balances.borrow_mut(user_addr);
    assert!(*current_balance >= amount, E_INSUFFICIENT_USER_BALANCE);

    // 从用户资金池中提取
    let withdraw_coin = coin::take(&mut pool.user_treasury, amount, ctx);
    transfer::public_transfer(withdraw_coin, user_addr);

    // 更新用户余额
    *current_balance = *current_balance - amount;

    // 发射事件
    event::emit(UserWithdrewnEvent {
        user: user_addr,
        amount,
        remaining_balance: *current_balance,
    });
}

// === 期权相关功能 ===

// 5. 为期权预留资金（从平台资金中预留）
public fun reserve_funds<T>(
    pool: &mut LPPool<T>,
    option_id: u64,
    potential_payout: u64,
    ctx: &mut TxContext,
): bool {
    // 权限检查
    let submitter_addr = ctx.sender();
    assert!(pool.authorized_submitters.contains(&submitter_addr), E_NOT_AUTHORIZED_SUBMITTER);
    assert!(!pool.paused, E_POOL_PAUSED);

    // 检查是否有足够的可用资金
    // max potential_payout = user premium * 20
    if (pool.available_balance < potential_payout) {
        return false
    };

    // 执行预留
    pool.available_balance = pool.available_balance - potential_payout;
    pool.reserved_balance = pool.reserved_balance + potential_payout;

    // 发射事件
    event::emit(FundsReservedEvent {
        option_id,
        amount: potential_payout,
        remaining_available: pool.available_balance,
        total_reserved: pool.reserved_balance,
    });

    true
}

// 6. 收取用户权利金（从用户账户扣除，转入平台资金池）
public fun collect_premium<T>(
    pool: &mut LPPool<T>,
    user_addr: address,
    premium_amount: u64,
    ctx: &mut TxContext,
) {
    // 权限检查
    let submitter_addr = ctx.sender();
    assert!(pool.authorized_submitters.contains(&submitter_addr), E_NOT_AUTHORIZED_SUBMITTER);
    assert!(!pool.paused, E_POOL_PAUSED);
    assert!(premium_amount > 0, E_INVALID_AMOUNT);

    // 检查用户余额
    assert!(pool.user_balances.contains(user_addr), E_USER_NOT_FOUND);
    let user_balance = pool.user_balances.borrow_mut(user_addr);
    assert!(*user_balance >= premium_amount, E_INSUFFICIENT_USER_BALANCE);

    // 将权利金从用户资金池转移到平台资金池
    let premium_coin = coin::take(&mut pool.user_treasury, premium_amount, ctx);
    coin::put(&mut pool.treasury, premium_coin);
    pool.available_balance = pool.available_balance + premium_amount;

    // 从用户账户扣除权利金
    *user_balance = *user_balance - premium_amount;

    // 发射事件
    event::emit(PremiumCollectedEvent {
        user: user_addr,
        amount: premium_amount,
        user_remaining_balance: *user_balance,
        total_available: pool.available_balance,
    });
}

// 7. 支付用户盈利（从平台资金池转入用户账户）
public fun pay_user_profit<T>(
    pool: &mut LPPool<T>,
    user_addr: address,
    profit_amount: u64,
    ctx: &mut TxContext,
) {
    // 权限检查
    let liquidator_addr = ctx.sender();
    assert!(pool.authorized_liquidators.contains(&liquidator_addr), E_NOT_AUTHORIZED_LIQUIDATOR);
    assert!(profit_amount > 0, E_INVALID_AMOUNT);

    // 检查平台资金是否充足
    assert!(pool.reserved_balance >= profit_amount, E_INSUFFICIENT_RESERVE);

    // 从平台资金池转移到用户资金池
    let profit_coin = coin::take(&mut pool.treasury, profit_amount, ctx);
    coin::put(&mut pool.user_treasury, profit_coin);

    // 更新平台资金状态
    pool.reserved_balance = pool.reserved_balance - profit_amount;

    // 更新用户余额
    if (pool.user_balances.contains(user_addr)) {
        let user_balance = pool.user_balances.borrow_mut(user_addr);
        *user_balance = *user_balance + profit_amount;
    } else {
        pool.user_balances.add(user_addr, profit_amount);
    };

    let new_user_balance = *pool.user_balances.borrow(user_addr);

    // 发射事件
    event::emit(UserProfitPaidEvent {
        user: user_addr,
        amount: profit_amount,
        new_user_balance,
    });
}

// 8. 用户的期权到期失败时释放预留资金（预留资金转为平台可用资金）
public fun release_reserved_funds<T>(
    pool: &mut LPPool<T>,
    reserved_amount: u64,
    ctx: &mut TxContext,
) {
    // 权限检查
    let liquidator_addr = ctx.sender();
    assert!(pool.authorized_liquidators.contains(&liquidator_addr), E_NOT_AUTHORIZED_LIQUIDATOR);

    // 资金检查
    assert!(pool.reserved_balance >= reserved_amount, E_INSUFFICIENT_RESERVE);

    // 释放预留资金，转为可用资金
    pool.reserved_balance = pool.reserved_balance - reserved_amount;
    pool.available_balance = pool.available_balance + reserved_amount;
}

// 9. 后端经授权的提交者提交用户的订单信息到合约中
entry fun submit_user_order<T>(
    pool: &mut LPPool<T>,
    order_id: string::String,
    user_addr: address,
    premium_amount: u64,
    option_id: u64,
    potential_payout: u64,
    ctx: &mut TxContext,
) {
    // 权限检查
    let submitter_addr = ctx.sender();
    assert!(pool.authorized_submitters.contains(&submitter_addr), E_NOT_AUTHORIZED_SUBMITTER);
    assert!(!pool.paused, E_POOL_PAUSED);

    // 检查用户余额
    assert!(pool.user_balances.contains(user_addr), E_USER_NOT_FOUND);
    let user_balance = pool.user_balances.borrow_mut(user_addr);
    assert!(*user_balance >= premium_amount, E_INSUFFICIENT_USER_BALANCE);

    collect_premium(pool, user_addr, premium_amount, ctx);

    let is_reserved = reserve_funds(pool, option_id, potential_payout, ctx);
    assert!(is_reserved, E_INSUFFICIENT_RESERVE);

    event::emit(UserOrderSubmittedEvent {
        order_id,
        user_addr,
        premium_amount,
        option_id,
        potential_payout,
    });
}

// 10. 对过期订单进行清算
entry fun liquidate_expired_order<T>(
    pool: &mut LPPool<T>,
    option_id: u64,
    user_addr: address,
    initial_reserved_amount: u64, // 为该期权最初预留的资金量
    payout_amount: u64,           // 如果用户盈利，支付给用户的金额 (如果亏损则为 0)
    ctx: &mut TxContext,
) {
    // 权限检查
    let liquidator_addr = ctx.sender();
    assert!(pool.authorized_liquidators.contains(&liquidator_addr), E_NOT_AUTHORIZED_LIQUIDATOR);
    assert!(!pool.paused, E_POOL_PAUSED);
    assert!(initial_reserved_amount > 0, E_INVALID_AMOUNT); // 必须有预留资金

    // 确保支付金额不超过最初预留金额
    assert!(payout_amount <= initial_reserved_amount, E_INVALID_AMOUNT);

    // 如果有盈利支付，则调用 pay_user_profit
    // pay_user_profit 会将资金从 treasury 转移到 user_treasury，并更新 user_balances
    // 同时，它会从 pool.reserved_balance 中扣除 payout_amount
    if (payout_amount > 0) {
        pay_user_profit(pool, user_addr, payout_amount, ctx);
    };

    // 释放剩余的预留资金到可用资金池
    // initial_reserved_amount - payout_amount 是这笔订单未支付给用户但仍被预留的资金
    let amount_to_release = initial_reserved_amount - payout_amount;
    if (amount_to_release > 0) {
        // release_reserved_funds 会将资金从 pool.reserved_balance 转移到 pool.available_balance
        release_reserved_funds(pool, amount_to_release, ctx);
    };

    // 发射清算事件
    event::emit(OrderLiquidatedEvent {
        option_id,
        user_addr,
        liquidator: liquidator_addr,
        reserved_released_amount: amount_to_release,
        payout_to_user_amount: payout_amount,
        new_available_balance: pool.available_balance,
        new_reserved_balance: pool.reserved_balance,
    });
}


// 11. 新建一个池子
entry fun create_new_pool<T>(
    auth_control: &AuthControl,
    new_coin_type: String,
    ctx: &mut TxContext,
) {
    assert!(auth_control.admin.contains(&ctx.sender()), E_NOT_AUTHORIZED_ADMIN);

    let mut new_pool = LPPool<T> {
        id: object::new(ctx),
        treasury: balance::zero<T>(),
        available_balance: 0,
        reserved_balance: 0,
        user_treasury: balance::zero<T>(),
        user_balances: table::new(ctx),
        admin: ctx.sender(),
        authorized_submitters: vector::empty<address>(),
        authorized_liquidators: vector::empty<address>(),
        paused: false,
        min_reserve_ratio: 20,
    };

    vector::push_back(&mut new_pool.authorized_liquidators, ctx.sender());
    vector::push_back(&mut new_pool.authorized_submitters, ctx.sender());

    event::emit(LPPoolCreatedEvent {
        creator: ctx.sender(),
        treasury_type: new_coin_type,
    });

    transfer::share_object(new_pool);
}

// === 查询函数 ===

// 获取池子状态
public fun get_pool_status<T>(pool: &LPPool<T>): (u64, u64, u64, u64) {
    (
        pool.treasury.value(), // 平台总资金
        pool.available_balance, // 平台可用资金
        pool.reserved_balance, // 平台预留资金
        pool.user_treasury.value(), // 用户总资金
    )
}

// 获取用户余额
public fun get_user_balance<T>(pool: &LPPool<T>, user: address): u64 {
    if (pool.user_balances.contains(user)) {
        *pool.user_balances.borrow(user)
    } else {
        0
    }
}

// 检查是否可以预留资金
public fun can_reserve_funds<T>(pool: &LPPool<T>, amount: u64): bool {
    !pool.paused && pool.available_balance >= amount
}

// 检查用户是否有足够余额支付权利金
public fun can_pay_premium<T>(pool: &LPPool<T>, user: address, amount: u64): bool {
    if (!pool.user_balances.contains(user)) {
        false
    } else {
        *pool.user_balances.borrow(user) >= amount
    }
}

// 检查是否是授权的提交者
public fun is_authorized_submitter<T>(pool: &LPPool<T>, addr: address): bool {
    pool.authorized_submitters.contains(&addr)
}

// 检查是否是授权的清算者
public fun is_authorized_liquidator<T>(pool: &LPPool<T>, addr: address): bool {
    pool.authorized_liquidators.contains(&addr)
}

//=======测试代码=======
#[test_only]
use sui::test_scenario as ts;

// 定义测试用户
#[test_only]
const ADMIN: address = @0x1;
#[test_only]
const SUBMITTER1: address = @0x2;
#[test_only]
const LIQUIDATOR1: address = @0x3;
#[test_only]
const USER1: address = @0x4;

// 初始化的测试
#[test]
fun test_contracts_init() {
    let mut ts = ts::begin(ADMIN);
    {
        init(ts.ctx());
    };

    ts.next_tx(ADMIN);
    let pool: LPPool<SUI> = ts.take_shared();

    // 验证ADMIN是否在授权提交者和清算者列表中
    assert!(is_authorized_submitter(&pool, ADMIN), E_AUTHORIZED_SUBMITTER_ALREADY_EXISTS);
    assert!(is_authorized_liquidator(&pool, ADMIN), E_AUTHORIZED_LIQUIDATOR_ALREADY_EXISTS);
    ts::return_shared(pool);
    ts.end();
}

#[test, expected_failure(abort_code = E_AUTHORIZED_SUBMITTER_ALREADY_EXISTS)]
fun test_add_authorized_submitter() {
    let mut ts = ts::begin(ADMIN);
    {
        init(ts.ctx());
    };

    ts.next_tx(ADMIN);

    // 获取共享对象 LPPool
    let mut pool: LPPool<SUI> = ts.take_shared();
    {
        ts::next_tx(&mut ts, ADMIN);
        let ctx = ts.ctx();
        add_authorized_submitter(&mut pool, SUBMITTER1, ctx);
        // 验证 SUBMITTER1 已被添加
        assert!(is_authorized_submitter(&pool, SUBMITTER1), E_AUTHORIZED_SUBMITTER_ALREADY_EXISTS);

        add_authorized_submitter(&mut pool, SUBMITTER1, ctx);
    };
    ts::return_shared(pool);
    ts.end();
}

#[test, expected_failure(abort_code = E_AUTHORIZED_LIQUIDATOR_ALREADY_EXISTS)]
fun test_add_authorized_liquidator() {
    let mut ts = ts::begin(ADMIN);
    {
        init(ts.ctx());
    };

    ts.next_tx(ADMIN);

    // 获取共享对象 LPPool
    let mut pool: LPPool<SUI> = ts.take_shared();
    {
        ts::next_tx(&mut ts, ADMIN);
        let ctx = ts.ctx();
        add_authorized_liquidator(&mut pool, LIQUIDATOR1, ctx);
        // 验证 LIQUIDATOR1 已被添加
        assert!(
            is_authorized_liquidator(&pool, LIQUIDATOR1),
            E_AUTHORIZED_LIQUIDATOR_ALREADY_EXISTS,
        );

        add_authorized_liquidator(&mut pool, LIQUIDATOR1, ctx);
    };
    ts::return_shared(pool);
    ts.end();
}

// sui client call \
//   --package 0x8bef74c68ec9fccb92f517ce8f9dba6ff81fbd6790d5397947647bc26a4bf246 \
//   --module lpcontrol \
//   --function is_authorized_liquidator \
//   --type-args "0x2::sui::SUI" \
//   --args 0x738eeacc9ea2ba03ba1570ed657cb89ea5a84453b514c4a48b4e7281b1472bbb  0x56e6362fd530999ec320fcf8b7ab06d9175fdd49ac32aec3ef3d924b7f1cbaa0

// sui client call \
//   --package 0x8bef74c68ec9fccb92f517ce8f9dba6ff81fbd6790d5397947647bc26a4bf246 \
//   --module lpcontrol \
//   --function add_authorized_liquidator \
//   --type-args "0x2::sui::SUI" \
//   --args 0x738eeacc9ea2ba03ba1570ed657cb89ea5a84453b514c4a48b4e7281b1472bbb  0x950c70f8d82f7e7fef4e2fd46fe714e091a35b7e0c015552b5971966630b2d9f
