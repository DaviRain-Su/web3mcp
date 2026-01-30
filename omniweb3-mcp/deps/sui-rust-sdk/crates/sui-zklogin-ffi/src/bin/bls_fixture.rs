use sui_crypto::bls12381::Bls12381PrivateKey;
use sui_crypto::Signer;

fn to_hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write;
        let _ = write!(out, "{byte:02x}");
    }
    out
}

fn main() {
    let seed = [1u8; 32];
    let key = Bls12381PrivateKey::new(seed).expect("invalid key");
    let message = b"sui-sdk-zig-bls-fixture";
    let signature = key.try_sign(message).expect("sign failed");
    let public_key = key.public_key();

    let output = format!(
        "{{\"message_hex\":\"{}\",\"public_key_hex\":\"{}\",\"signature_hex\":\"{}\"}}",
        to_hex(message),
        to_hex(public_key.as_bytes()),
        to_hex(signature.as_bytes()),
    );
    println!("{output}");
}
