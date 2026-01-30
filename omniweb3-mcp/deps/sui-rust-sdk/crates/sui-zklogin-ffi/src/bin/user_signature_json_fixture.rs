use base64ct::Base64;
use base64ct::Encoding;
use sui_crypto::ed25519::Ed25519PrivateKey;
use sui_crypto::Signer;
use sui_sdk_types::UserSignature;

fn main() {
    let message = b"sui-sdk-zig-user-signature-json-fixture";
    let key = Ed25519PrivateKey::new([10u8; 32]);
    let sig = key.try_sign(message).expect("sign");
    let user_sig = UserSignature::Simple(sig);
    let user_signature_json = serde_json::to_string(&user_sig).expect("json");

    let output = serde_json::json!({
        "message_base64": Base64::encode_string(message),
        "user_signature_json": user_signature_json
    });

    println!("{}", output.to_string());
}
