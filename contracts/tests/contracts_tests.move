#[test_only]
module contracts::contracts_tests;

use sui::test_scenario as ts;
use contracts::lpcontrol::{Self, LPPool};
use sui::sui::SUI;

// 定义测试用户
const ADMIN: address = @0x1;
const SUBMITTER1: address = @0x2;
const LIQUIDATOR1: address = @0x3;
const USER1: address = @0x4;

// 初始化的测试，可以不实现
#[test]
fun test_contracts_init() {
    let ts = ts::begin(ADMIN);
    // {
    //     let ctx = ts.ctx();
    //     lpcontrol::init(ctx);
    // };
    let pool = ts::take_shared<LPPool<SUI>>(&ts);
    // 验证ADMIN是否在授权提交者和清算者列表中
    assert!(lpcontrol::is_authorized_submitter(&pool, ADMIN), 0);
    assert!(lpcontrol::is_authorized_liquidator(&pool, ADMIN), 0);
    ts::return_shared(pool);
    ts.end();
}

#[test]
fun test_add_authorized_submitter() {
     let mut ts = ts::begin(ADMIN);
    // {
    //     let ctx = ts.ctx();
    //     lpcontrol::init(ctx);
    // };

    // 获取共享对象 LPPool
    let mut pool = ts::take_shared<LPPool<SUI>>(&ts);
    {
        ts::next_tx(&mut ts, ADMIN);
        let ctx = ts.ctx();
        lpcontrol::add_authorized_submitter(&mut pool, SUBMITTER1, ctx);
        // 验证 SUBMITTER1 已被添加
        assert!(lpcontrol::is_authorized_submitter(&pool, SUBMITTER1), 0);
    };
    ts::return_shared(pool);
    ts.end();
}

#[test]
fun test_add_authorized_liquidator() {
    let mut ts = ts::begin(ADMIN);
    // {
    //     let ctx = ts.ctx();
    //     lpcontrol::init(ctx);
    // };

    // 获取共享对象 LPPool
    let mut pool = ts::take_shared<LPPool<SUI>>(&ts);
    {
        ts::next_tx(&mut ts, ADMIN);
        let ctx = ts.ctx();
        lpcontrol::add_authorized_liquidator(&mut pool, LIQUIDATOR1, ctx);
        // 验证 LIQUIDATOR1 已被添加
        assert!(lpcontrol::is_authorized_liquidator(&pool, LIQUIDATOR1), 0);
    };
    ts::return_shared(pool);
    ts.end();
}