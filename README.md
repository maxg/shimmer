Shimmer
=======

**Touchstone ~ OpenID Connect**


Development
-----------

Opening in VS Code should prompt to *Reopen in Container* using the dev container config.


Deployment
----------

Running commands in the dev container...

In the `config` directory:

- create `config.sh` following the example
- create `sp-{encrypt,signing}-{cert,key}.pem` by running:  
  `/etc/shibboleth/keygen.sh -b -h $shimmer_hostname -n sp-signing`  
  `/etc/shibboleth/keygen.sh -b -h $shimmer_hostname -n sp-encrypt`
- create `idp-jwks.json` using `server/generate-keys.js`
- create directory `clients` containing client JSON config files

Then in `setup`:

- create `packer.conf.json` following the example
- `./pack HEAD`
- create `terraform.tfvars` following the example
- `terraform init -backend-config=terraform.tfvars`
- `terraform apply`


Icon
----

 + [JoyPixels sheaf of rice](https://www.joypixels.com/emoji/sheaf-of-rice)
