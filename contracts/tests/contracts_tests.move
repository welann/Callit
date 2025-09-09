// #[test_only]
// module contracts::contracts_tests;

// use sui::test_scenario as ts;
// use contracts::lpcontrol::{Self,LPPool,init};
// use sui::sui::SUI;


// const E_POOL_PAUSED: u64 = 0;
// const E_INVALID_AMOUNT: u64 = 1;
// const E_NOT_ADMIN: u64 = 2;
// const E_INSUFFICIENT_AVAILABLE_BALANCE: u64 = 3;
// const E_INSUFFICIENT_RESERVE: u64 = 4;
// const E_NOT_AUTHORIZED_SUBMITTER: u64 = 5;
// const E_NOT_AUTHORIZED_LIQUIDATOR: u64 = 6;
// // const E_NOT_AUTHORIZED_ADMIN: u64 = 7;
// const E_INSUFFICIENT_USER_BALANCE: u64 = 8;
// const E_USER_NOT_FOUND: u64 = 9;
// const E_AUTHORIZED_SUBMITTER_ALREADY_EXISTS: u64 = 10;
// const E_AUTHORIZED_LIQUIDATOR_ALREADY_EXISTS: u64 = 11;

// // 定义测试用户
// const ADMIN: address = @0x1;
// const SUBMITTER1: address = @0x2;
// const LIQUIDATOR1: address = @0x3;
// const USER1: address = @0x4;

// // 初始化的测试，可以不实现
// #[test]
// fun test_contracts_init() {
//     let mut ts = ts::begin(ADMIN);

//     {
//         init(ts.ctx());
//     };

//     ts.next_tx( ADMIN);
//     let pool:LPPool<SUI> = ts.take_shared();
//     // 验证ADMIN是否在授权提交者和清算者列表中
    
//     ts::return_shared(pool);
//     ts.end();
// }

// #[test, expected_failure(abort_code = E_AUTHORIZED_SUBMITTER_ALREADY_EXISTS)]
// fun test_add_authorized_submitter() {
//     let mut ts = ts::begin(ADMIN);
//     // {
//     //     let ctx = ts.ctx();
//     //     lpcontrol::init(ctx);
//     // };

//     // 获取共享对象 LPPool
//     let mut pool = ts::take_shared<LPPool<SUI>>(&ts);
//     {
//         ts::next_tx(&mut ts, ADMIN);
//         let ctx = ts.ctx();
//         lpcontrol::add_authorized_submitter(&mut pool, SUBMITTER1, ctx);
//         // 验证 SUBMITTER1 已被添加
//         assert!(lpcontrol::is_authorized_submitter(&pool, SUBMITTER1), 0);
//     };
//     ts::return_shared(pool);
//     ts.end();
// }

// #[test]
// fun test_add_authorized_liquidator() {
//     let mut ts = ts::begin(ADMIN);
//     // {
//     //     let ctx = ts.ctx();
//     //     lpcontrol::init(ctx);
//     // };

//     // 获取共享对象 LPPool
//     let mut pool = ts::take_shared<LPPool<SUI>>(&ts);
//     {
//         ts::next_tx(&mut ts, ADMIN);
//         let ctx = ts.ctx();
//         lpcontrol::add_authorized_liquidator(&mut pool, LIQUIDATOR1, ctx);
//         // 验证 LIQUIDATOR1 已被添加
//         assert!(lpcontrol::is_authorized_liquidator(&pool, LIQUIDATOR1), 0);
//     };
//     ts::return_shared(pool);
//     ts.end();
// }