use base64ct::Base64;
use base64ct::Encoding;
use sui_crypto::ed25519::Ed25519PrivateKey;
use sui_crypto::Signer;
use sui_sdk_types::MultisigAggregatedSignature;
use sui_sdk_types::MultisigCommittee;
use sui_sdk_types::MultisigMember;
use sui_sdk_types::MultisigMemberPublicKey;
use sui_sdk_types::MultisigMemberSignature;

fn main() {
    let message = b"sui-sdk-zig-multisig-fixture";

    let key0 = Ed25519PrivateKey::new([1u8; 32]);
    let key1 = Ed25519PrivateKey::new([2u8; 32]);

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

    let aggregated = MultisigAggregatedSignature::new(committee, signatures, bitmap);
    let bcs_bytes = bcs::to_bytes(&aggregated).expect("bcs");

    let output = serde_json::json!({
        "message_base64": Base64::encode_string(message),
        "signature_bcs_base64": Base64::encode_string(&bcs_bytes)
    });

    println!("{}", output.to_string());
}
