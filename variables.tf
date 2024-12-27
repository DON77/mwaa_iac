variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "max_workers" {
  description = "The maximum number of workers"
  type        = number
}

variable "region" {
  description = "Default region for env"
  type = string
}

variable "private_subnets"{
  description = " Private subnets to be created"
  type = list
  default = []
}

variable "public_subnets"{
  description = "Public subnets already a part of default VPC, this is for reference" 
  type = list 
  default =[]
}

variable "nat_gateway"{
  description = "We're reusing the existing NAT for our default vpc"
  type = string
  default ="nat-0edd6e97a61b58443"
}

variable "account_id" {
  description = "Master account value"
  type = string
  default = "" 
}

variable "prod_instance"{
  description = "This points to the database instance to be used for retriving data"
  type = string
  default = ""
}