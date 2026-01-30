use base64ct::Base64;
use base64ct::Encoding;
use sui_crypto::ed25519::Ed25519PrivateKey;
use sui_crypto::secp256k1::Secp256k1PrivateKey;
use sui_crypto::secp256r1::Secp256r1PrivateKey;
use sui_crypto::Signer;
use sui_sdk_types::SimpleSignature;

fn main() {
    let message = b"sui-sdk-zig-simple-signature-fixture";

    let ed_key = Ed25519PrivateKey::new([3u8; 32]);
    let k1_key = Secp256k1PrivateKey::new([4u8; 32]).expect("secp256k1 key");
    let r1_key = Secp256r1PrivateKey::new([5u8; 32]);

    let ed_sig = ed_key.try_sign(message).expect("ed25519");
    let k1_sig = k1_key.try_sign(message).expect("secp256k1");
    let r1_sig = r1_key.try_sign(message).expect("secp256r1");

    let ed_simple = SimpleSignature::Ed25519 {
        signature: ed_sig,
        public_key: ed_key.public_key(),
    };
    let k1_simple = SimpleSignature::Secp256k1 {
        signature: k1_sig,
        public_key: k1_key.public_key(),
    };
    let r1_simple = SimpleSignature::Secp256r1 {
        signature: r1_sig,
        public_key: r1_key.public_key(),
    };

    let ed_bcs = bcs::to_bytes(&ed_simple).expect("bcs");
    let k1_bcs = bcs::to_bytes(&k1_simple).expect("bcs");
    let r1_bcs = bcs::to_bytes(&r1_simple).expect("bcs");

    let output = serde_json::json!({
        "message_base64": Base64::encode_string(message),
        "ed25519_bcs_base64": Base64::encode_string(&ed_bcs),
        "secp256k1_bcs_base64": Base64::encode_string(&k1_bcs),
        "secp256r1_bcs_base64": Base64::encode_string(&r1_bcs)
    });

    println!("{}", output.to_string());
}
