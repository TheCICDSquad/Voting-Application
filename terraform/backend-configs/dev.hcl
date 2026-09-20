bucket         = "craftista-terraform-state"
key            = "env/dev/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "craftista-terraform-locks"
encrypt        = true
