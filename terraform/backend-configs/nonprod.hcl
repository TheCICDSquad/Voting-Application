bucket         = "craftista-terraform-state"
key            = "env/nonprod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "craftista-terraform-locks"
encrypt        = true
