# SSL tools

Scripts and configs to aid with some openSSL operations.

## Requirements

- bash
- openssl
- crudini

## Examples

Generate a certificate authority:

```
./generate-ca.sh
```

Generate an SSL certificate for `localhost` using your own authority:

```
./generate-host.sh -n localhost -n 127.0.0.1 -n ::1
```

Now, import your root certificate as an certificate authority in your
OS/browser, and you can then use your self created SSL certificates without
those pesky SSL warnings. You probably shouldn't do this outside of
development.

Keep in mind that this self-created certificate authority has no restrictions
on what hosts it can sign certificates for. Keep its files and passphrase
secure, because if anyone gets their hands on these HTTPS traffic to and from
your machine is no longer safe.

