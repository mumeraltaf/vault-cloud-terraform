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

provider "openstack" {
  auth_url                      = data.vault_kv_secret_v2.openstack-app-creds.data.OS_AUTH_URL
  application_credential_id     = data.vault_kv_secret_v2.openstack-app-creds.data.OS_APPLICATION_CREDENTIAL_ID
  application_credential_secret = data.vault_kv_secret_v2.openstack-app-creds.data.OS_APPLICATION_CREDENTIAL_SECRET
  region                        = data.vault_kv_secret_v2.openstack-app-creds.data.OS_REGION_NAME
}

data "openstack_compute_instance_v2" "instance" {
  id = "51ddb9d1-af27-49ff-a014-312d6c2d094d"
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



