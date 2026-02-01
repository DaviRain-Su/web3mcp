use std::fs;
use std::path::Path;

fn main() {
    let out_dir = std::env::var("OUT_DIR").expect("OUT_DIR not set");
    let out_path = Path::new(&out_dir).join("router_impl.rs");

    let helper_sections = [
        "src/tools/move/automation/move_auto_helpers.rs",
        "src/tools/move/resolution/move_resolve_helpers.rs",
        "src/tools/intent/intent_helpers.rs",
    ];

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
        "src/tools/evm/evm_tools.rs",
    ];

    let mut content = String::new();

    // 1) Plain impl block for helper methods (not tools)
    content.push_str("#[allow(clippy::empty_line_after_outer_attr, clippy::manual_find, clippy::bool_comparison, clippy::get_first, clippy::too_many_arguments, clippy::unnecessary_to_owned, clippy::type_complexity, clippy::redundant_locals, clippy::bind_instead_of_map, clippy::unwrap_or_default)]\n");
    content.push_str("impl SuiMcpServer {\n");
    for section in helper_sections {
        let data = fs::read_to_string(section)
            .unwrap_or_else(|e| panic!("Failed to read {}: {}", section, e));
        content.push_str(&data);
        content.push('\n');
    }
    content.push_str("}\n\n");

    // 2) Tool router impl block (tools only)
    content.push_str("#[allow(clippy::empty_line_after_outer_attr, clippy::manual_find, clippy::bool_comparison, clippy::get_first, clippy::too_many_arguments, clippy::unnecessary_to_owned, clippy::type_complexity, clippy::redundant_locals, clippy::bind_instead_of_map, clippy::unwrap_or_default)]\n");
    content.push_str("#[tool_router]\nimpl SuiMcpServer {\n");
    for section in sections {
        let data = fs::read_to_string(section)
            .unwrap_or_else(|e| panic!("Failed to read {}: {}", section, e));
        content.push_str(&data);
        content.push('\n');
    }
    content.push_str("}\n");

    fs::write(&out_path, content).expect("Failed to write router_impl.rs");

    for section in helper_sections {
        println!("cargo:rerun-if-changed={}", section);
    }
    for section in sections {
        println!("cargo:rerun-if-changed={}", section);
    }
}
