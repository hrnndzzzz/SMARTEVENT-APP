-- Update the check on existing OTP tables.

ALTER TABLE otp_tokens
    DROP CONSTRAINT IF EXISTS otp_tokens_purpose_check;

ALTER TABLE otp_tokens
    ADD CONSTRAINT otp_tokens_purpose_check
    CHECK (purpose IN ('registration', 'initial_setup', 'password_reset'));
