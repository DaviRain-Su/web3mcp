use std::fs;
use std::path::Path;

fn main() {
    let out_dir = std::env::var("OUT_DIR").expect("OUT_DIR not set");
    let out_path = Path::new(&out_dir).join("router_impl.rs");

    let sections = [
        "src/tools/read/balances/read_balances.rs",
        "src/tools/read/objects/read_objects.rs",
        "src/tools/read/transactions/read_transactions.rs",
        "src/tools/intent/nl_intent.rs",
        "src/tools/intent/templates/transaction_templates.rs",
        "src/tools/auth/zklogin/zklogin.rs",
        "src/tools/auth/keystore/keystore.rs",
        "src/tools/tx/pay/tx_build.rs",
        "src/tools/tx/inspections/tx_sim.rs",
        "src/tools/tx/staking/tx_stakes.rs",
        "src/tools/tx/queries/checkpoints.rs",
        "src/tools/tx/queries/tx_queries.rs",
        "src/tools/tx/queries/coin_queries.rs",
        "src/tools/move/schema/move_schema.rs",
        "src/tools/move/schema/move_suggest.rs",
        "src/tools/move/resolution/move_resolve.rs",
        "src/tools/move/dynamic/dapp_manifest.rs",
        "src/tools/move/automation/move_auto.rs",
        "src/tools/move/dynamic/move_dynamic.rs",
        "src/tools/graphql/core/graphql_tools.rs",
        "src/tools/rpc/service/rpc_tools.rs",
        "src/tools/crypto/signature/crypto_tools.rs",
        "src/tools/system/gas/system_gas.rs",
        "src/tools/system/events/system_events.rs",
        "src/tools/system/stats/system_stats.rs",
        "src/tools/system/coins/coin_read.rs",
        "src/tools/system/chain/chain_info.rs",
    ];

    let mut content = String::from("#[tool_router]\nimpl SuiMcpServer {\n");
    for section in sections {
        let data = fs::read_to_string(section)
            .unwrap_or_else(|e| panic!("Failed to read {}: {}", section, e));
        content.push_str(&data);
        content.push('\n');
    }
    content.push_str("}\n");

    fs::write(&out_path, content).expect("Failed to write router_impl.rs");

    for section in sections {
        println!("cargo:rerun-if-changed={}", section);
    }
}
