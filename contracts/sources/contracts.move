/*
/// Module: contracts
module contracts::contracts;
*/

// For Move coding conventions, see
// https://docs.sui.io/concepts/sui-move-concepts/conventions

module contracts::contracts;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;
use sui::table::{Self, Table};

const E_POOL_PAUSED: u64 = 0;
const E_INVALID_AMOUNT: u64 = 1;
const E_NOT_ADMIN: u64 = 2;
const E_INSUFFICIENT_AVAILABLE_BALANCE: u64 = 3;
const E_INSUFFICIENT_RESERVE: u64 = 4;

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

// 简化的 LP 资金池
public struct LPPool<phantom T> has key {
    id: UID,
    // === 核心资金管理 ===
    treasury: Balance<T>, // 池子总资金
    available_balance: u64, // 可用资金（未被期权占用）
    reserved_balance: u64, // 预留资金（被期权占用）
    // === LP 管理 ===
    // lp_deposits: Table<address, u64>, // LP存入记录（地址 -> 金额）
    total_lp_deposits: u64, // LP总存入金额
    // === 权限控制 ===
    admin: address, // 管理员地址
    authorized_submitters: vector<address>, // 授权的订单提交者
    authorized_liquidators: vector<address>, // 授权的清算者
    // === 基础配置 ===
    paused: bool, // 紧急暂停开关
    min_reserve_ratio: u64, // 最小预留比例（防止资金全部被占用）
}

// 1. LP 存入流动性
public entry fun deposit_liquidity<T>(pool: &mut LPPool<T>, coins: Coin<T>, ctx: &mut TxContext) {
    let depositor_addr = ctx.sender();
    let deposit_amount = coins.value();

    // 基础检查
    assert!(!pool.paused, E_POOL_PAUSED);
    assert!(deposit_amount > 0, E_INVALID_AMOUNT);

    // 更新资金
    coin::put(&mut pool.treasury, coins);
    pool.available_balance = pool.available_balance + deposit_amount;
    pool.total_lp_deposits = pool.total_lp_deposits + deposit_amount;

    // // 记录存入
    // if(pool.lp_deposits.contains(depositor_addr)){
    //     let current_deposit = pool.lp_deposits.borrow_mut(depositor_addr);
    //     *current_deposit = *current_deposit + deposit_amount;
    // } else {
    //     pool.lp_deposits.add(depositor_addr, deposit_amount);
    // };

    // 发射事件
    event::emit(LiquidityDepositedEvent {
        depositor: depositor_addr,
        amount: deposit_amount,
        total_available: pool.available_balance,
    });
}

// 2. LP 提取流动性（仅管理员可执行）
public entry fun withdraw_liquidity<T>(
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
    let min_required = pool.reserved_balance * (10000 + pool.min_reserve_ratio) / 10000;
    assert!(remaining_balance >= min_required, E_INSUFFICIENT_RESERVE);

    // 执行提取
    pool.available_balance = pool.available_balance - amount;
    let withdraw_coin = coin::take(&mut pool.treasury, amount, ctx);
    transfer::public_transfer(withdraw_coin, ctx.sender());

    // 发射事件
    event::emit(LiquidityWithdrawnEvent {
        admin: ctx.sender(),
        to,
        amount,
        remaining_available: pool.available_balance,
    });
}


