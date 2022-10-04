terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "3.8.2"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.48.0"
    }
    tls = {
      source  = "hashicorp/tls"
    }
  }
}

provider "tls" {}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

provider "vault" {
  address = "https://umer-vault-cluster-public-vault-9a8f3c75.2c8b14ba.z1.hashicorp.cloud:8200"
}

data "vault_kv_secret_v2" "openstack-app-creds" {
  mount = "secret"
  name  = "openstack-app-creds"
}

data "vault_kv_secret_v2" "envfile" {
  mount = "secret"
  name  = "envfile"
}

provider "openstack" {
  auth_url                      = data.vault_kv_secret_v2.openstack-app-creds.data.OS_AUTH_URL
  application_credential_id     = data.vault_kv_secret_v2.openstack-app-creds.data.OS_APPLICATION_CREDENTIAL_ID
  application_credential_secret = data.vault_kv_secret_v2.openstack-app-creds.data.OS_APPLICATION_CREDENTIAL_SECRET
  region                        = data.vault_kv_secret_v2.openstack-app-creds.data.OS_REGION_NAME
}

resource "vault_mount" "terraform-secrets" {
  path        = "terraform-secrets"
  type        = "kv"
  options     = { version = "1" }
  description = "Terraform Generated Secrets"
}


resource "vault_kv_secret" "ssh_key" {
  path = "${vault_mount.terraform-secrets.path}/ssh_key"
  data_json = jsonencode(
    {
      private_key = tls_private_key.ssh.private_key_pem,
      public_key = tls_private_key.ssh.public_key_pem
    }
  )
}



resource "openstack_compute_keypair_v2" "adp-terraform-network-key" {
  name       = "adp-terraform-network"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "openstack_compute_instance_v2" "test-instance" {
  depends_on      = [openstack_compute_keypair_v2.adp-terraform-network-key]
  name            = "test-instance"
  flavor_name     = "r3.xsmall"
  image_name      = "NeCTAR Debian 11 (Bullseye) amd64"
  key_pair        = openstack_compute_keypair_v2.adp-terraform-network-key.name
  security_groups = ["default", "ssh-int", "https-int", "https-all"]

  connection {
    user        = "debian"
    host        = openstack_compute_instance_v2.test-instance.access_ip_v4
    private_key = tls_private_key.ssh.private_key_pem
  }

  provisioner file {
    content = data.vault_kv_secret_v2.envfile.data.env
    destination = "/home/debian/.env"
  }

}

