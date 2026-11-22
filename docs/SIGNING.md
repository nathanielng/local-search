# Signing

A rebuilt app signed ad-hoc gets a new identity every time, so macOS forgets the permissions you gave it
(Desktop, Documents, Downloads) and Spotlight/Quick Find silently omit files from those folders.

`scripts/build-app.sh` therefore signs with a local self-signed certificate called **LocalSearch Dev**
(override with `LOCALSEARCH_SIGN_IDENTITY`). If it isn't in your keychain it falls back to ad-hoc.

## Create the certificate (once per Mac)

```bash
D=$(mktemp -d) && cd "$D" && PW=$(openssl rand -hex 12)
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 \
  -subj "/CN=LocalSearch Dev" -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -passout pass:$PW
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P "$PW" -T /usr/bin/codesign
cd - && rm -rf "$D"
```

The certificate does not need to be marked trusted. The private key stays in the login keychain only.
After the first build signed this way, macOS asks for folder access one last time; later builds keep it.
