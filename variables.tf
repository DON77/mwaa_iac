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
  default = "nat-06a1591a09a44c958"#"nat-0edd6e97a61b58443"
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

variable "route_table_id" {
  description = "Importing existing route table"
  type = string
  default ="rtb-0f2a88f0687ec3450"
}

variable security_group_id {
  description = "We'll use created security group"
  default = "sg-0847536e6a975e26a"
}
