# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, email: **security@estabilis.io**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 48 hours and provide a timeline for the fix.

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest release | Yes |
| Previous minor | Best effort |
| Older | No |

## Security Best Practices

When deploying this module in production:

1. **Disable local accounts**: Set `local_account_disabled = true` with Azure AD group IDs
2. **Restrict API server access**: Set `authorized_ip_ranges` to platform NAT gateway IP only
3. **Enable resource locks**: Set `storage_protect_critical = true` on critical storage
4. **Use Private Endpoints**: Where available (ACR Premium)
5. **Rotate credentials**: Regularly rotate Docker Hub tokens and hub registrar tokens
6. **Monitor audit logs**: Enable `diagnostics_enabled = true` with Log Analytics
