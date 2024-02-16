variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_ami" {
  description = "instance ami"
  type        = string
  default     = "ami-0c7217cdde317cfec"
}

variable "instance_type" {
  description = "instance ami"
  type        = string
  default     = "t2.micro"
}

variable "name_tag" {
  description = "instance ami"
  type        = string
  default     = "techstarter-test"
}

variable "availability_zones" {
  description = "instance ami"
  type        = list(any)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "pem_key" {
  description = "instance ami"
  type        = string
  default     = "mvpfoundry"
}