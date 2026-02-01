use serde_json::json;
use serde_json::Value;

/// Best-effort EVM calldata classifier for common token ops.
///
/// Returns a machine-friendly label + a small, UI-friendly summary.
pub fn classify_calldata(data_hex: &str) -> Option<Value> {
    let hexs = data_hex.strip_prefix("0x").unwrap_or(data_hex);
    if hexs.len() < 8 {
        return None;
    }
    let sel = &hexs[..8].to_lowercase();

    match sel.as_str() {
        // ERC20 approve(address,uint256)
        "095ea7b3" => {
            // reuse decode logic: selector + spender(32) + amount(32)
            if hexs.len() < 8 + 64 + 64 {
                Some(json!({"label":"erc20_approve","selector":sel}))
            } else {
                let spender_hex = &hexs[8 + 24..8 + 64];
                let amount_hex = &hexs[8 + 64..8 + 64 + 64];
                let spender = format!("0x{}", spender_hex.to_lowercase());
                Some(json!({
                    "label": "erc20_approve",
                    "selector": sel,
                    "spender": spender,
                    "amount_hex": format!("0x{}", amount_hex),
                }))
            }
        }

        // ERC20 increaseAllowance(address,uint256)
        "39509351" => {
            if hexs.len() < 8 + 64 + 64 {
                Some(json!({"label":"erc20_increase_allowance","selector":sel}))
            } else {
                let spender_hex = &hexs[8 + 24..8 + 64];
                let amount_hex = &hexs[8 + 64..8 + 64 + 64];
                Some(json!({
                    "label": "erc20_increase_allowance",
                    "selector": sel,
                    "spender": format!("0x{}", spender_hex.to_lowercase()),
                    "amount_hex": format!("0x{}", amount_hex),
                }))
            }
        }

        // ERC20 decreaseAllowance(address,uint256)
        "a457c2d7" => {
            if hexs.len() < 8 + 64 + 64 {
                Some(json!({"label":"erc20_decrease_allowance","selector":sel}))
            } else {
                let spender_hex = &hexs[8 + 24..8 + 64];
                let amount_hex = &hexs[8 + 64..8 + 64 + 64];
                Some(json!({
                    "label": "erc20_decrease_allowance",
                    "selector": sel,
                    "spender": format!("0x{}", spender_hex.to_lowercase()),
                    "amount_hex": format!("0x{}", amount_hex),
                }))
            }
        }

        // ERC20 transfer(address,uint256)
        "a9059cbb" => {
            if hexs.len() < 8 + 64 + 64 {
                Some(json!({"label":"erc20_transfer","selector":sel}))
            } else {
                let to_hex = &hexs[8 + 24..8 + 64];
                let amount_hex = &hexs[8 + 64..8 + 64 + 64];
                Some(json!({
                    "label": "erc20_transfer",
                    "selector": sel,
                    "to": format!("0x{}", to_hex.to_lowercase()),
                    "amount_hex": format!("0x{}", amount_hex),
                }))
            }
        }

        // Permit (EIP-2612): permit(address,address,uint256,uint256,uint8,bytes32,bytes32)
        "d505accf" => Some(json!({"label":"erc20_permit_eip2612","selector":sel})),

        // Permit2 allowance transferFrom: transferFrom(address,address,uint160,address)
        // (common selector; Permit2 has several. We'll start with the most common call.)
        "36c78516" => Some(json!({"label":"permit2_transfer_from","selector":sel})),

        _ => Some(json!({"label":"unknown","selector":sel})),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classify_unknown() {
        let v = classify_calldata("0xdeadbeef").unwrap();
        assert_eq!(v["label"], "unknown");
    }

    #[test]
    fn classify_approve() {
        // approve(spender=0x11..11, amount=1)
        let spender = "1111111111111111111111111111111111111111";
        let amount = "0000000000000000000000000000000000000000000000000000000000000001";
        let data = format!("0x095ea7b3{:0>64}{}", spender, amount);
        let v = classify_calldata(&data).unwrap();
        assert_eq!(v["label"], "erc20_approve");
        assert_eq!(v["spender"], format!("0x{}", spender));
    }
}
