use ethers::types::U256;

/// Decode ERC20 `approve(address,uint256)` calldata.
///
/// Returns (spender_address, amount) where spender is a checksummed-agnostic lowercased 0x-hex string.
pub fn decode_erc20_approve(data_hex: &str) -> Option<(String, U256)> {
    let hexs = data_hex.strip_prefix("0x").unwrap_or(data_hex);
    if hexs.len() < 8 + 64 + 64 {
        return None;
    }
    if !hexs[..8].eq_ignore_ascii_case("095ea7b3") {
        return None;
    }

    // ABI encoding: selector(4) + spender(32) + amount(32)
    // spender is right-aligned in its 32-byte slot; last 20 bytes are address.
    let spender_hex = &hexs[8 + 24..8 + 64];
    let amount_hex = &hexs[8 + 64..8 + 64 + 64];

    let spender = format!("0x{}", spender_hex.to_lowercase());
    let amount = U256::from_str_radix(amount_hex, 16).ok()?;
    Some((spender, amount))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_approve_ok() {
        // approve(0x1111...1111, 0x2a)
        let spender = "1111111111111111111111111111111111111111";
        let amount = "000000000000000000000000000000000000000000000000000000000000002a";
        let data = format!(
            "0x095ea7b3{:0>64}{}",
            spender, amount
        );
        let (s, a) = decode_erc20_approve(&data).expect("decode");
        assert_eq!(s, format!("0x{}", spender));
        assert_eq!(a, U256::from(42u64));
    }

    #[test]
    fn decode_approve_rejects_other_selector() {
        let data = "0xdeadbeef";
        assert!(decode_erc20_approve(data).is_none());
    }
}
