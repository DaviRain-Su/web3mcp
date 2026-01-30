use base64ct::Base64;
use base64ct::Base64UrlUnpadded;
use base64ct::Encoding;
use sha2::Digest;
use sha2::Sha256;
use sui_crypto::secp256r1::Secp256r1PrivateKey;
use sui_crypto::Signer;
use sui_sdk_types::PasskeyAuthenticator;
use sui_sdk_types::SimpleSignature;
use sui_sdk_types::UserSignature;

fn main() {
    let message = b"sui-sdk-zig-user-signature-json-passkey";
    let challenge = Base64UrlUnpadded::encode_string(message);

    let client_data_json = format!(
        "{{\"type\":\"webauthn.get\",\"challenge\":\"{challenge}\",\"origin\":\"https://example.com\"}}"
    );
    let authenticator_data = b"auth-data-passkey-json".to_vec();

    let mut hasher = Sha256::new();
    hasher.update(client_data_json.as_bytes());
    let digest = hasher.finalize();

    let mut signing_input = Vec::with_capacity(authenticator_data.len() + digest.len());
    signing_input.extend_from_slice(&authenticator_data);
    signing_input.extend_from_slice(&digest);

    let key = Secp256r1PrivateKey::new([13u8; 32]);
    let signature = key.try_sign(&signing_input).expect("signature");
    let public_key = key.public_key();
    let simple_sig = SimpleSignature::Secp256r1 {
        signature,
        public_key,
    };

    let passkey = PasskeyAuthenticator::new(authenticator_data, client_data_json, simple_sig)
        .expect("passkey");
    let user_sig = UserSignature::Passkey(passkey);
    let user_signature_json = serde_json::to_string(&user_sig).expect("json");

    let output = serde_json::json!({
        "message_base64": Base64::encode_string(message),
        "user_signature_json": user_signature_json
    });

    println!("{}", output.to_string());
}
