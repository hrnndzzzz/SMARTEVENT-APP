-- Allow the OTP purposes used by the current authentication flows.
-- The original CREATE TABLE migration does not update an already-existing
-- otp_tokens table, so replace its older check constraint in place.

ALTER TABLE otp_tokens
    DROP CONSTRAINT IF EXISTS otp_tokens_purpose_check;

ALTER TABLE otp_tokens
    ADD CONSTRAINT otp_tokens_purpose_check
    CHECK (purpose IN ('registration', 'initial_setup', 'password_reset'));