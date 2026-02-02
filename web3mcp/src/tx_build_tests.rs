#[cfg(test)]
mod tests {
    use crate::Web3McpServer;
    use serde_json::json;
    use std::str::FromStr;
    use sui_types::base_types::{ObjectID, SequenceNumber, SuiAddress};
    use sui_types::digests::ObjectDigest;
    use sui_types::transaction::{ObjectArg, TransactionData, TransactionKind};

    #[test]
    fn build_7k_swap_tx_produces_bytes() {
        let quote = json!({
            "tokenIn": "0x2::sui::SUI",
            "tokenOut": "0x2::sui::SUI",
            "swapAmountWithDecimal": "1000",
            "returnAmountWithDecimal": "900",
            "routes": [],
            "swaps": [
                {
                    "amount": "1000",
                    "calls": [
                        {
                            "target": "0x2::dummy::swap",
                            "typeArguments": [],
                            "arguments": [
                                {"kind": "input_coin"},
                                {"kind": "pure", "type": "u64", "value": 1}
                            ]
                        }
                    ]
                }
            ]
        });

        let sender = SuiAddress::from_str(
            "0x1111111111111111111111111111111111111111111111111111111111111111",
        )
        .expect("valid sender");

        let input_coin_id = ObjectID::from_hex_literal(
            "0x2222222222222222222222222222222222222222222222222222222222222222",
        )
        .expect("valid object id");
        let gas_coin_id = ObjectID::from_hex_literal(
            "0x3333333333333333333333333333333333333333333333333333333333333333",
        )
        .expect("valid gas id");

        let digest = ObjectDigest::new([1u8; 32]);
        let input_ref = (input_coin_id, SequenceNumber::from(1), digest);
        let gas_ref = (gas_coin_id, SequenceNumber::from(1), digest);

        let config_id = ObjectID::from_hex_literal(
            "0x4444444444444444444444444444444444444444444444444444444444444444",
        )
        .expect("valid config id");
        let vault_id = ObjectID::from_hex_literal(
            "0x5555555555555555555555555555555555555555555555555555555555555555",
        )
        .expect("valid vault id");

        let config_arg = ObjectArg::SharedObject {
            id: config_id,
            initial_shared_version: SequenceNumber::from(1),
            mutability: sui_types::transaction::SharedObjectMutability::Immutable,
        };
        let vault_arg = ObjectArg::SharedObject {
            id: vault_id,
            initial_shared_version: SequenceNumber::from(1),
            mutability: sui_types::transaction::SharedObjectMutability::Mutable,
        };

        let swaps = quote
            .get("swaps")
            .and_then(|v| v.as_array())
            .cloned()
            .expect("swaps array");
        let grouped = Web3McpServer::group_7k_swaps(&swaps).expect("group swaps");
        let route_amounts = vec![1000u64];

        let pt = Web3McpServer::build_7k_swap_pt(
            sender,
            "0x2::sui::SUI",
            "0x2::sui::SUI",
            1000,
            900,
            850,
            0,
            None,
            &grouped,
            &route_amounts,
            &[input_ref],
            config_arg,
            vault_arg,
        )
        .expect("build pt");

        let tx_data = TransactionData::new(
            TransactionKind::programmable(pt),
            sender,
            gas_ref,
            1_000_000,
            1,
        );

        let tx_bytes_b64 = Web3McpServer::encode_tx_bytes(&tx_data).expect("encode bytes");
        assert!(!tx_bytes_b64.is_empty());
    }
}
