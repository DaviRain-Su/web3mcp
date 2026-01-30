use std::cell::RefCell;
use std::ptr;
use std::slice;

use sui_crypto::bls12381::Bls12381VerifyingKey;
use sui_crypto::bls12381::ValidatorCommitteeSignatureVerifier;
use sui_crypto::zklogin::ZkloginVerifier;
use sui_crypto::Verifier;
use sui_sdk_types::Bls12381PublicKey;
use sui_sdk_types::Bls12381Signature;
use sui_sdk_types::Jwk;
use sui_sdk_types::SimpleSignature;
use sui_sdk_types::ValidatorAggregatedSignature;
use sui_sdk_types::ValidatorCommittee;
use sui_sdk_types::ValidatorSignature;
use sui_sdk_types::ZkLoginAuthenticator;
use sui_sdk_types::ZkLoginInputs;

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = RefCell::new(None);
}

fn set_last_error(message: impl ToString) {
    let message = message.to_string();
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = Some(message);
    });
}

fn clear_last_error() {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = None;
    });
}

unsafe fn slice_from_raw<'a>(ptr: *const u8, len: usize) -> Result<&'a [u8], String> {
    if ptr.is_null() {
        if len == 0 {
            return Ok(&[]);
        }
        return Err("null pointer with non-zero length".to_string());
    }
    Ok(unsafe { slice::from_raw_parts(ptr, len) })
}

fn verify_with_inputs(
    jwk: Jwk,
    inputs: ZkLoginInputs,
    signature: SimpleSignature,
    message: &[u8],
    max_epoch: u64,
    use_dev_vk: bool,
) -> Result<(), String> {
    let mut verifier = if use_dev_vk {
        ZkloginVerifier::new_dev()
    } else {
        ZkloginVerifier::new_mainnet()
    };

    verifier.jwks_mut().insert(inputs.jwk_id().clone(), jwk);

    let authenticator = ZkLoginAuthenticator {
        inputs,
        max_epoch,
        signature,
    };

    verifier
        .verify(message, &authenticator)
        .map_err(|err| err.to_string())
}

#[unsafe(no_mangle)]
pub extern "C" fn sui_zklogin_verify_bcs(
    jwk_ptr: *const u8,
    jwk_len: usize,
    inputs_ptr: *const u8,
    inputs_len: usize,
    signature_ptr: *const u8,
    signature_len: usize,
    message_ptr: *const u8,
    message_len: usize,
    max_epoch: u64,
    use_dev_vk: bool,
) -> i32 {
    clear_last_error();

    let result = (|| -> Result<(), String> {
        let jwk_bytes = unsafe { slice_from_raw(jwk_ptr, jwk_len) }?;
        let inputs_bytes = unsafe { slice_from_raw(inputs_ptr, inputs_len) }?;
        let signature_bytes = unsafe { slice_from_raw(signature_ptr, signature_len) }?;
        let message_bytes = unsafe { slice_from_raw(message_ptr, message_len) }?;

        let jwk: Jwk = bcs::from_bytes(jwk_bytes).map_err(|err| err.to_string())?;
        let inputs: ZkLoginInputs = bcs::from_bytes(inputs_bytes).map_err(|err| err.to_string())?;
        let signature: SimpleSignature =
            bcs::from_bytes(signature_bytes).map_err(|err| err.to_string())?;

        verify_with_inputs(jwk, inputs, signature, message_bytes, max_epoch, use_dev_vk)
    })();

    match result {
        Ok(()) => 0,
        Err(message) => {
            set_last_error(message);
            1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn sui_zklogin_verify_json(
    jwk_json_ptr: *const u8,
    jwk_json_len: usize,
    inputs_json_ptr: *const u8,
    inputs_json_len: usize,
    signature_json_ptr: *const u8,
    signature_json_len: usize,
    message_ptr: *const u8,
    message_len: usize,
    max_epoch: u64,
    use_dev_vk: bool,
) -> i32 {
    clear_last_error();

    let result = (|| -> Result<(), String> {
        let jwk_bytes = unsafe { slice_from_raw(jwk_json_ptr, jwk_json_len) }?;
        let inputs_bytes = unsafe { slice_from_raw(inputs_json_ptr, inputs_json_len) }?;
        let signature_bytes = unsafe { slice_from_raw(signature_json_ptr, signature_json_len) }?;
        let message_bytes = unsafe { slice_from_raw(message_ptr, message_len) }?;

        let jwk: Jwk = serde_json::from_slice(jwk_bytes).map_err(|err| err.to_string())?;
        let inputs: ZkLoginInputs =
            serde_json::from_slice(inputs_bytes).map_err(|err| err.to_string())?;
        let signature: SimpleSignature =
            serde_json::from_slice(signature_bytes).map_err(|err| err.to_string())?;

        verify_with_inputs(jwk, inputs, signature, message_bytes, max_epoch, use_dev_vk)
    })();

    match result {
        Ok(()) => 0,
        Err(message) => {
            set_last_error(message);
            1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn sui_zklogin_last_error_message(buf: *mut u8, buf_len: usize) -> usize {
    let message = LAST_ERROR.with(|cell| cell.borrow().clone());
    let Some(message) = message else {
        return 0;
    };

    if buf.is_null() || buf_len == 0 {
        return message.len();
    }

    let copy_len = buf_len.min(message.len());
    unsafe {
        ptr::copy_nonoverlapping(message.as_ptr(), buf, copy_len);
    }
    copy_len
}

#[unsafe(no_mangle)]
pub extern "C" fn sui_zklogin_clear_error() {
    clear_last_error();
}

#[unsafe(no_mangle)]
pub extern "C" fn sui_bls_verify(
    public_key_ptr: *const u8,
    public_key_len: usize,
    signature_ptr: *const u8,
    signature_len: usize,
    message_ptr: *const u8,
    message_len: usize,
) -> i32 {
    clear_last_error();

    let result = (|| -> Result<(), String> {
        let public_key_bytes = unsafe { slice_from_raw(public_key_ptr, public_key_len) }?;
        let signature_bytes = unsafe { slice_from_raw(signature_ptr, signature_len) }?;
        let message_bytes = unsafe { slice_from_raw(message_ptr, message_len) }?;

        let public_key =
            Bls12381PublicKey::from_bytes(public_key_bytes).map_err(|err| err.to_string())?;
        let signature =
            Bls12381Signature::from_bytes(signature_bytes).map_err(|err| err.to_string())?;
        let verifying_key =
            Bls12381VerifyingKey::new(&public_key).map_err(|err| err.to_string())?;
        verifying_key
            .verify(message_bytes, &signature)
            .map_err(|err| err.to_string())
    })();

    match result {
        Ok(()) => 0,
        Err(message) => {
            set_last_error(message);
            1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn sui_bls_verify_validator_signature(
    committee_ptr: *const u8,
    committee_len: usize,
    signature_ptr: *const u8,
    signature_len: usize,
    message_ptr: *const u8,
    message_len: usize,
) -> i32 {
    clear_last_error();

    let result = (|| -> Result<(), String> {
        let committee_bytes = unsafe { slice_from_raw(committee_ptr, committee_len) }?;
        let signature_bytes = unsafe { slice_from_raw(signature_ptr, signature_len) }?;
        let message_bytes = unsafe { slice_from_raw(message_ptr, message_len) }?;

        let committee: ValidatorCommittee =
            bcs::from_bytes(committee_bytes).map_err(|err| err.to_string())?;
        let signature: ValidatorSignature =
            bcs::from_bytes(signature_bytes).map_err(|err| err.to_string())?;

        let verifier =
            ValidatorCommitteeSignatureVerifier::new(committee).map_err(|err| err.to_string())?;
        verifier
            .verify(message_bytes, &signature)
            .map_err(|err| err.to_string())
    })();

    match result {
        Ok(()) => 0,
        Err(message) => {
            set_last_error(message);
            1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn sui_bls_verify_validator_aggregated_signature(
    committee_ptr: *const u8,
    committee_len: usize,
    signature_ptr: *const u8,
    signature_len: usize,
    message_ptr: *const u8,
    message_len: usize,
) -> i32 {
    clear_last_error();

    let result = (|| -> Result<(), String> {
        let committee_bytes = unsafe { slice_from_raw(committee_ptr, committee_len) }?;
        let signature_bytes = unsafe { slice_from_raw(signature_ptr, signature_len) }?;
        let message_bytes = unsafe { slice_from_raw(message_ptr, message_len) }?;

        let committee: ValidatorCommittee =
            bcs::from_bytes(committee_bytes).map_err(|err| err.to_string())?;
        let signature: ValidatorAggregatedSignature =
            bcs::from_bytes(signature_bytes).map_err(|err| err.to_string())?;

        let verifier =
            ValidatorCommitteeSignatureVerifier::new(committee).map_err(|err| err.to_string())?;
        verifier
            .verify(message_bytes, &signature)
            .map_err(|err| err.to_string())
    })();

    match result {
        Ok(()) => 0,
        Err(message) => {
            set_last_error(message);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_json_sets_error_message() {
        let bad = b"{";
        let rc = sui_zklogin_verify_json(
            bad.as_ptr(),
            bad.len(),
            bad.as_ptr(),
            bad.len(),
            bad.as_ptr(),
            bad.len(),
            ptr::null(),
            0,
            0,
            false,
        );
        assert_ne!(rc, 0);

        let needed = sui_zklogin_last_error_message(ptr::null_mut(), 0);
        assert!(needed > 0);

        let mut buf = vec![0u8; needed];
        let written = sui_zklogin_last_error_message(buf.as_mut_ptr(), buf.len());
        assert!(written > 0);
    }
}
