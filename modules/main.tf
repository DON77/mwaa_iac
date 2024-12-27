provider "aws" {
  region = "eu-central-1"  
}

resource "aws_s3_bucket" "terraform_state" {
  bucket         = "buycycle-mwaa-tf-state"  
  tags ={ "Environment":"buycycle mwaa" }
}

resource "aws_dynamodb_table" "buycycle_mwaa_tf_state_lock" {
  name           = "buycycle-mwaa-tf-state-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    "Environment" = "buycycle mwaa"
  }
}


