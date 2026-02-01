use ethers::types::U256;

pub fn bump_u256(old: Option<U256>, suggested: Option<U256>, multiplier_bps: u64) -> U256 {
    let mult = U256::from(multiplier_bps);
    let denom = U256::from(10_000u64);

    let mut candidates: Vec<U256> = Vec::new();

    if let Some(s) = suggested {
        // s * mult / 10000
        let bumped = s
            .checked_mul(mult)
            .unwrap_or(s)
            .checked_div(denom)
            .unwrap_or(s);
        candidates.push(bumped);
    }
    if let Some(o) = old {
        let bumped = o
            .checked_mul(mult)
            .unwrap_or(o)
            .checked_div(denom)
            .unwrap_or(o);
        candidates.push(bumped);
        candidates.push(o.saturating_add(U256::from(1u64)));
    }

    candidates
        .into_iter()
        .max()
        .unwrap_or_else(|| U256::from(0u64))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bump_prefers_suggested_mult() {
        let v = bump_u256(Some(U256::from(100u64)), Some(U256::from(200u64)), 12_000);
        assert_eq!(v, U256::from(240u64));
    }

    #[test]
    fn bump_prefers_old_plus_one_if_needed() {
        let v = bump_u256(Some(U256::from(100u64)), Some(U256::from(0u64)), 10_000);
        assert_eq!(v, U256::from(101u64));
    }
}
