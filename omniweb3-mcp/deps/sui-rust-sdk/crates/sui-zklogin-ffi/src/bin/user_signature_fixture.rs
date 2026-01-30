use base64ct::Base64;
use base64ct::Encoding;
use sui_crypto::ed25519::Ed25519PrivateKey;
use sui_crypto::Signer;
use sui_sdk_types::UserSignature;

fn main() {
    let message = b"sui-sdk-zig-user-signature-fixture";
    let key = Ed25519PrivateKey::new([9u8; 32]);
    let sig = key.try_sign(message).expect("sign");
    let user_sig = UserSignature::Simple(sig);

    let output = serde_json::json!({
        "message_base64": Base64::encode_string(message),
        "user_signature_base64": user_sig.to_base64()
    });

    println!("{}", output.to_string());
}
