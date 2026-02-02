use std::sync::Mutex;

static CWD_LOCK: Mutex<()> = Mutex::new(());

fn with_temp_cwd<F: FnOnce()>(f: F) {
    let _g = CWD_LOCK.lock().unwrap();
    let tmp = tempfile::tempdir().expect("tempdir");
    let old = std::env::current_dir().expect("cwd");
    std::env::set_current_dir(tmp.path()).expect("set cwd");
    f();
    std::env::set_current_dir(old).expect("restore cwd");
}

#[test]
fn sqlite_migrations_are_idempotent_and_links_work() {
    with_temp_cwd(|| {
        let conn = web3mcp::utils::evm_confirm_store::connect().expect("connect");

        // second connect shouldn't error even with existing columns
        let _ = web3mcp::utils::evm_confirm_store::connect().expect("connect2");

        // insert a dummy pending row
        let tx = web3mcp::types::EvmTxRequest {
            chain_id: 1,
            from: "0x1111111111111111111111111111111111111111".to_string(),
            to: "0x2222222222222222222222222222222222222222".to_string(),
            value_wei: "0".to_string(),
            nonce: None,
            gas_limit: None,
            max_fee_per_gas_wei: None,
            max_priority_fee_per_gas_wei: None,
            data_hex: Some("0x".to_string()),
        };

        let now = web3mcp::utils::evm_confirm_store::now_ms();
        let id_swap = "swap_1";
        let id_app = "app_1";
        let hash = web3mcp::utils::evm_confirm_store::tx_summary_hash(&tx);

        web3mcp::utils::evm_confirm_store::insert_pending(id_swap, &tx, now, now + 10000, &hash)
            .expect("insert swap");
        web3mcp::utils::evm_confirm_store::insert_pending(id_app, &tx, now, now + 10000, &hash)
            .expect("insert approve");

        web3mcp::utils::evm_confirm_store::set_expected_allowance(
            id_swap,
            "0xtoken",
            "0xspender",
            "123",
        )
        .expect("set_expected_allowance");

        web3mcp::utils::evm_confirm_store::set_approve_link(id_swap, id_app).expect("link approve");
        web3mcp::utils::evm_confirm_store::set_swap_link(id_app, id_swap).expect("link swap");

        let swap_row = web3mcp::utils::evm_confirm_store::get_row(&conn, id_swap)
            .expect("get swap")
            .expect("swap exists");
        assert_eq!(swap_row.expected_token.as_deref(), Some("0xtoken"));
        assert_eq!(swap_row.expected_spender.as_deref(), Some("0xspender"));
        assert_eq!(swap_row.required_allowance_raw.as_deref(), Some("123"));
        assert_eq!(swap_row.approve_confirmation_id.as_deref(), Some(id_app));

        let approve_row = web3mcp::utils::evm_confirm_store::get_row(&conn, id_app)
            .expect("get approve")
            .expect("approve exists");
        assert_eq!(approve_row.swap_confirmation_id.as_deref(), Some(id_swap));
    });
}
