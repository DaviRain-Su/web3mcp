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

        // Permit (EIP-2612): permit(address owner,address spender,uint256 value,uint256 deadline,uint8 v,bytes32 r,bytes32 s)
        "d505accf" => {
            if hexs.len() < 8 + 64 * 7 {
                Some(json!({"label":"erc20_permit_eip2612","selector":sel}))
            } else {
                let owner = format!("0x{}", hexs[8 + 24..8 + 64].to_lowercase());
                let spender = format!("0x{}", hexs[8 + 64 + 24..8 + 64 + 64].to_lowercase());
                let value_hex = format!("0x{}", &hexs[8 + 64 * 2..8 + 64 * 3]);
                let deadline_hex = format!("0x{}", &hexs[8 + 64 * 3..8 + 64 * 4]);
                let v_hex = format!("0x{}", &hexs[8 + 64 * 4..8 + 64 * 5]);
                let r = format!("0x{}", &hexs[8 + 64 * 5..8 + 64 * 6]);
                let s = format!("0x{}", &hexs[8 + 64 * 6..8 + 64 * 7]);
                Some(json!({
                    "label": "erc20_permit_eip2612",
                    "selector": sel,
                    "owner": owner,
                    "spender": spender,
                    "value_hex": value_hex,
                    "deadline_hex": deadline_hex,
                    "v_hex": v_hex,
                    "r": r,
                    "s": s,
                }))
            }
        }

        // Permit2 transferFrom(address from,address to,uint160 amount,address token)
        // Selector: 0x36c78516 (Permit2)
        "36c78516" => {
            if hexs.len() < 8 + 64 * 4 {
                Some(json!({"label":"permit2_transfer_from","selector":sel}))
            } else {
                let from = format!("0x{}", hexs[8 + 24..8 + 64].to_lowercase());
                let to = format!("0x{}", hexs[8 + 64 + 24..8 + 64 + 64].to_lowercase());
                let amount_hex = format!("0x{}", &hexs[8 + 64 * 2..8 + 64 * 3]);
                let token = format!("0x{}", hexs[8 + 64 * 3 + 24..8 + 64 * 4].to_lowercase());
                Some(json!({
                    "label": "permit2_transfer_from",
                    "selector": sel,
                    "from": from,
                    "to": to,
                    "amount_hex": amount_hex,
                    "token": token,
                }))
            }
        }

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

    #[test]
    fn classify_permit2_transfer_from() {
        // transferFrom(from=0x11.., to=0x22.., amount=1, token=0x33..)
        let from = "1111111111111111111111111111111111111111";
        let to = "2222222222222222222222222222222222222222";
        let token = "3333333333333333333333333333333333333333";
        let amount = "0000000000000000000000000000000000000000000000000000000000000001";
        let data = format!("0x36c78516{:0>64}{:0>64}{}{:0>64}", from, to, amount, token);
        let v = classify_calldata(&data).unwrap();
        assert_eq!(v["label"], "permit2_transfer_from");
        assert_eq!(v["from"], format!("0x{}", from));
        assert_eq!(v["to"], format!("0x{}", to));
        assert_eq!(v["token"], format!("0x{}", token));
    }
}
