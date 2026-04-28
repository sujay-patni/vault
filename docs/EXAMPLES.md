# Examples

Vault stores different kinds of encrypted items in one local vault. Every field below is encrypted inside the vault payload.

## Password

Use for website or app credentials.

- Title: `GitHub`
- Username: `you@example.com`
- Password: generated password
- URL: `https://github.com`
- Tags: `work, dev`
- Notes: recovery hints or setup notes

## Secure Note

Use when you only need a title and encrypted body.

- Title: `Home safe code`
- Note: code, context, and instructions
- Tags: `personal, home`

## Recovery Codes

Use for backup codes from two-factor authentication setup.

- Title: `Google recovery codes`
- Service: `Google`
- Recovery codes: one code per line
- Tags: `2fa, recovery`

## API Key

Use for tokens and developer secrets.

- Title: `Stripe test key`
- Service: `Stripe`
- Key or token: secret value
- Account or email: owner/account context
- Tags: `dev, api`

## Wi-Fi

Use for private network credentials.

- Title: `Home Wi-Fi`
- Network name: `MyNetwork`
- Password: Wi-Fi password
- Security type: `WPA2/WPA3`
- Tags: `home`

## Payment Card

Use for card details you want available offline.

- Title: `Travel card`
- Cardholder
- Card number
- Expiry
- CVV
- PIN
- Tags: `travel, finance`

## Identity

Use for IDs and documents.

- Title: `Passport`
- Document type: `Passport`
- Document number
- Name
- Issue date
- Expiry date
- Tags: `identity, travel`

## Finance

Use for bank/account metadata.

- Title: `Primary bank`
- Institution
- Account or customer ID
- IFSC, routing, or SWIFT
- Notes
- Tags: `banking`
