use base64ct::Base64;
use base64ct::Encoding;
use sui_crypto::ed25519::Ed25519PrivateKey;
use sui_crypto::Signer;
use sui_sdk_types::Bitmap;
use sui_sdk_types::MultisigAggregatedSignature;
use sui_sdk_types::MultisigCommittee;
use sui_sdk_types::MultisigMember;
use sui_sdk_types::MultisigMemberPublicKey;
use sui_sdk_types::MultisigMemberSignature;
use sui_sdk_types::UserSignature;

fn main() {
    let message = b"sui-sdk-zig-legacy-multisig-fixture";

    let key0 = Ed25519PrivateKey::new([6u8; 32]);
    let key1 = Ed25519PrivateKey::new([7u8; 32]);

    let sig0 = key0.try_sign(message).expect("sign0");
    let sig1 = key1.try_sign(message).expect("sign1");

    let member0 = MultisigMember::new(MultisigMemberPublicKey::Ed25519(key0.public_key()), 1);
    let member1 = MultisigMember::new(MultisigMemberPublicKey::Ed25519(key1.public_key()), 1);

    let committee = MultisigCommittee::new(vec![member0, member1], 2);
    let signatures = vec![
        MultisigMemberSignature::Ed25519(sig0),
        MultisigMemberSignature::Ed25519(sig1),
    ];
    let bitmap = 0b11u16;

    let mut aggregated = MultisigAggregatedSignature::new(committee, signatures, bitmap);
    let mut legacy_bitmap = Bitmap::new();
    legacy_bitmap.insert(0);
    legacy_bitmap.insert(1);
    aggregated.with_legacy_bitmap(legacy_bitmap);

    let user_sig = UserSignature::Multisig(aggregated);

    let output = serde_json::json!({
        "message_base64": Base64::encode_string(message),
        "user_signature_base64": user_sig.to_base64()
    });

    println!("{}", output.to_string());
}
