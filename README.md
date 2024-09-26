# Proxmox services

Terraform/Ansible scripts to setup self-hosted services on Proxmox

```bash
./terraform/

terraform init

terraform apply

terraform destroy -target=proxmox_lxc.traefik
```

```bash
./ansible/

ansible-playbook ./playbooks/traefik.yml
```

```bash
ssh-keygen -R "traefik.test"; ssh-keygen -R "10.0.1.1"
```


```bash
apt install certbot
wget https://github.com/joohoi/acme-dns-certbot-joohoi/raw/master/acme-dns-auth.py -O /etc/letsencrypt/acme-dns-auth2.py
chmod +x /etc/letsencrypt/acme-dns-auth.py
sed -i ''-e '1s:#!/usr/bin/env python:#!/usr/bin/env python3:' /etc/letsencrypt/acme-dns-auth.py
echo "Follow the instructions and update DNS CNAME in CloudFlare..."
certbot certonly --manual --manual-auth-hook /etc/letsencrypt/acme-dns-auth.py --rsa-key-size 4096 --preferred-challenges dns --debug-challenges -d \*.damoreira.ml -d damoreira.ml

_IN=/etc/letsencrypt/live/damoreira.ml/fullchain.pem
_OUT=~/traefik_certificate
cat $_IN | base64 | tr '\n' ' ' | sed --expression='s/\ //g' > $_OUT

_IN=/etc/letsencrypt/live/damoreira.ml/privkey.pem
_OUT=~/traefik_key
cat $_IN | base64 | tr '\n' ' ' | sed --expression='s/\ //g' > $_OUT

echo "Update /etc/traefik/acme.json and add the following certificate:"
echo "{
        "domain": {
          "main": "example.com"
        },
        "certificate": "\<certificate\>",
        "key": "\<key\>",
        "Store": "default"
      }"
```

