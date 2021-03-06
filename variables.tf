variable "user" {
  description = "This is going to be the Org username"
}

variable "public_key" {
  description = "Public key info"
}

variable "private_key" {
  description = "Private key info"
}

variable "key_name" {
  description = "Desired name of AWS key pair"
  default     = "demo-terraform"
}

variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "us-east-2"
}

variable "aws_ami_linux" {
  default = "ami-038e35de01603d84e"
}

variable "aws_ami_windows" {
  default = "ami-0e315da6b15c55161"
}

variable "aws_instance_username" {
  default = ""
}

variable "aws_instance_password" {
  default = ""
}

