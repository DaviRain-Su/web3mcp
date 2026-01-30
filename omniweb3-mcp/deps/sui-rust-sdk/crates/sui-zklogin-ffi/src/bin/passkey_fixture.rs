use base64ct::Base64;
use base64ct::Base64UrlUnpadded;
use base64ct::Encoding;
use sha2::Digest;
use sha2::Sha256;
use sui_crypto::secp256r1::Secp256r1PrivateKey;
use sui_crypto::Signer;
use sui_sdk_types::PasskeyAuthenticator;
use sui_sdk_types::SimpleSignature;

fn main() {
    let message = b"sui-sdk-zig-passkey-fixture";
    let challenge = Base64UrlUnpadded::encode_string(message);

    let client_data_json = format!(
        "{{\"type\":\"webauthn.get\",\"challenge\":\"{challenge}\",\"origin\":\"https://example.com\"}}"
    );
    let authenticator_data = b"auth-data-fixture".to_vec();

    let mut hasher = Sha256::new();
    hasher.update(client_data_json.as_bytes());
    let digest = hasher.finalize();

    let mut signing_input = Vec::with_capacity(authenticator_data.len() + digest.len());
    signing_input.extend_from_slice(&authenticator_data);
    signing_input.extend_from_slice(&digest);

    let key = Secp256r1PrivateKey::new([7u8; 32]);
    let signature = key.try_sign(&signing_input).expect("signature");
    let public_key = key.public_key();
    let simple_sig = SimpleSignature::Secp256r1 {
        signature,
        public_key,
    };

    let passkey = PasskeyAuthenticator::new(authenticator_data, client_data_json, simple_sig)
        .expect("passkey");
    let bcs_bytes = bcs::to_bytes(&passkey).expect("bcs");

    let output = serde_json::json!({
        "message_base64": Base64::encode_string(message),
        "passkey_bcs_base64": Base64::encode_string(&bcs_bytes)
    });

    println!("{}", output.to_string());
}
