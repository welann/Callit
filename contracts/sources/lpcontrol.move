// use sui::coin::{Self, Coin};
// use sui::event;
// use sui::table;
// use sui::balance;
// use sui::signer;
// use sui::address;
// use sui::uid;
// use sui::tx_context::{Self, TxContext};

// /// 简化的 LP 资金池
// struct LPPool<phantom T> has key {
//     id: UID,
    
//     // === 核心资金管理 ===
//     treasury: Balance<T>,                    // 池子总资金
//     available_balance: u64,                  // 可用资金（未被期权占用）
//     reserved_balance: u64,                   // 预留资金（被期权占用）
    
//     // === LP 管理 ===
//     lp_deposits: Table<address, u64>,        // LP存入记录（地址 -> 金额）
//     total_lp_deposits: u64,                  // LP总存入金额
    
//     // === 权限控制 ===
//     admin: address,                          // 管理员地址
//     authorized_submitters: vector<address>,  // 授权的订单提交者
//     authorized_liquidators: vector<address>, // 授权的清算者
    
//     // === 基础配置 ===
//     paused: bool,                           // 紧急暂停开关
//     min_reserve_ratio: u64,                 // 最小预留比例（防止资金全部被占用）
// }


// /// 1. LP 存入流动性
// public entry fun deposit_liquidity<T>(
//     pool: &mut LPPool<T>,
//     depositor: &signer,
//     coins: Coin<T>,
// ) {
//     let depositor_addr = signer::address_of(depositor);
//     let deposit_amount = coin::value(&coins);
    
//     // 基础检查
//     assert!(!pool.paused, E_POOL_PAUSED);
//     assert!(deposit_amount > 0, E_INVALID_AMOUNT);
    
//     // 更新资金
//     coin::put(&mut pool.treasury, coins);
//     pool.available_balance = pool.available_balance + deposit_amount;
//     pool.total_lp_deposits = pool.total_lp_deposits + deposit_amount;
    
//     // 记录存入
//     if (table::contains(&pool.lp_deposits, depositor_addr)) {
//         let current_deposit = table::borrow_mut(&mut pool.lp_deposits, depositor_addr);
//         *current_deposit = *current_deposit + deposit_amount;
//     } else {
//         table::add(&mut pool.lp_deposits, depositor_addr, deposit_amount);
//     };
    
//     // 发射事件
//     event::emit(LiquidityDeposited {
//         depositor: depositor_addr,
//         amount: deposit_amount,
//         total_available: pool.available_balance,
//     });
// }

// /// 2. LP 提取流动性（仅管理员可执行）
// public entry fun withdraw_liquidity<T>(
//     pool: &mut LPPool<T>,
//     admin: &signer,
//     to: address,
//     amount: u64,
//     ctx: &mut TxContext
// ): Coin<T> {
//     // 权限检查
//     assert!(signer::address_of(admin) == pool.admin, E_NOT_ADMIN);
//     assert!(!pool.paused, E_POOL_PAUSED);
//     assert!(amount > 0, E_INVALID_AMOUNT);
    
//     // 流动性检查 - 确保不影响期权赔付
//     assert!(pool.available_balance >= amount, E_INSUFFICIENT_AVAILABLE_BALANCE);
    
//     // 最小预留检查 - 防止池子被完全掏空
//     let total_balance = balance::value(&pool.treasury);
//     let remaining_balance = total_balance - amount;
//     let min_required = pool.reserved_balance * (10000 + pool.min_reserve_ratio) / 10000;
//     assert!(remaining_balance >= min_required, E_INSUFFICIENT_RESERVE);
    
//     // 执行提取
//     pool.available_balance = pool.available_balance - amount;
//     let withdraw_coin = coin::take(&mut pool.treasury, amount, ctx);
    
//     // 发射事件
//     event::emit(LiquidityWithdrawn {
//         admin: signer::address_of(admin),
//         to,
//         amount,
//         remaining_available: pool.available_balance,
//     });
    
//     withdraw_coin
// }
















