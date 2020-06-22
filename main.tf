#########################################
# Specify the provider and access details
#########################################
provider "aws" {
  region  = var.aws_region
  version = "~> 2.0"
}

##############################
# Setup key for authentication
##############################
resource "aws_key_pair" "auth" {
  key_name   = var.key_name
  public_key = var.public_key
}

module "vpc" {
  source  = "app.terraform.io/mtharpe/vpc/aws"
  version = "1.0.0"

  name = "${var.user}-demo-vpc"
  cidr = "10.0.0.0/16"

  azs = ["us-east-2a", "us-east-2b", "us-east-2c"]

  private_subnets  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  database_subnets = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  public_subnets   = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]

  create_database_subnet_group = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Terraform   = "true"
    Environment = "Demo"
  }
}

########################################
# List all availability zones to be used
########################################
data "aws_availability_zones" "available" {
}

########################
# Default Security group
########################
resource "aws_security_group" "default" {
  name        = "${var.user}-demo-tfe default sg"
  description = "Used in the terraform"
  vpc_id      = module.vpc.vpc_id

  # SSH access from the VPC and LocalIP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16", "0.0.0.0/0"]
  }

  ingress {
    from_port   = 5985
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16", "0.0.0.0/0"]
  }

  # RDP access from the VPC and LocalIP
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16", "0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16", "0.0.0.0/0"]
  }

  # HTTPS access from the VPC
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16", "0.0.0.0/0"]
  }

  # HTTP Jenkins 8080 access from the VPC
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16", "0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

##############
# Web Instance
##############
resource "aws_instance" "web-01" {
  tags = {
    Name = "${var.user}-web-01"
  }

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = "ubuntu"
    private_key = var.private_key
  }

  instance_type = "t2.micro"

  ami                    = var.aws_ami_linux
  key_name               = aws_key_pair.auth.id
  vpc_security_group_ids = [aws_security_group.default.id]
  subnet_id              = module.vpc.public_subnets[0]

  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init to finish...'; sleep 1; done",
      "sudo apt update && sleep $((RANDOM % 10)) && sudo apt update",
      "sudo apt install apache2 -y"
    ]
  }
}

#####################
# Management Instance
#####################
resource "aws_instance" "mgmt-01" {
  tags = {
    Name = "${var.user}-mgmt-01"
  }

  connection {
    host     = aws_instance.mgmt-01.public_ip
    type     = "winrm"
    user     = var.aws_instance_username
    password = var.aws_instance_password
  }

  instance_type           = "t2.medium"
  source_dest_check       = true
  disable_api_termination = false

  ami                    = var.aws_ami_windows
  key_name               = aws_key_pair.auth.id
  vpc_security_group_ids = [aws_security_group.default.id]
  subnet_id              = module.vpc.public_subnets[0]
  user_data              = <<EOF
<script>
  winrm quickconfig -q & winrm set winrm/config @{MaxTimeoutms="1800000"} & winrm set winrm/config/service @{AllowUnencrypted="true"} & winrm set winrm/config/service/auth @{Basic="true"}
</script>
<powershell>
netsh advfirewall firewall add rule name="WinRM in" protocol=TCP dir=in profile=any localport=5985 remoteip=any localip=any action=allow
net user ${var.aws_instance_username} '${var.aws_instance_password}' /add /y
net localgroup administrators ${var.aws_instance_username} /add
</powershell>
EOF

  provisioner "remote-exec" {
    inline = [
      "powershell -command Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole",
      "powershell -command Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer",
      "powershell -command Enable-WindowsOptionalFeature -Online -FeatureName IIS-CommonHttpFeatures",
      "powershell -command Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpErrors",
      "powershell -command Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpRedirect",
      "powershell -command Enable-WindowsOptionalFeature -Online -FeatureName IIS-ApplicationDevelopment"
    ]
  }
}

###################
# Jenkins Instances
###################
resource "aws_instance" "jenkins-01" {
  tags = {
    Name = "${var.user}-jenkins-01"
  }

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = "ubuntu"
    private_key = var.private_key
  }

  instance_type           = "t2.micro"
  source_dest_check       = true
  disable_api_termination = false

  ami                    = var.aws_ami_linux
  key_name               = aws_key_pair.auth.id
  vpc_security_group_ids = [aws_security_group.default.id]
  subnet_id              = module.vpc.public_subnets[1]

  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init to finish...'; sleep 1; done",
      "sudo apt update && sleep $((RANDOM % 10)) && sudo apt update",
      "sudo apt install zip default-jdk -y",
      "wget -q -O - http://pkg.jenkins-ci.org/debian/jenkins-ci.org.key | sudo apt-key add -",
      "sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'",
      "sudo add-apt-repository universe",
      "sudo apt-get update",
      "sudo apt-get install jenkins -y"
    ]
  }
}

###################
# Database Instance
###################
# resource "aws_db_instance" "default" {
#   allocated_storage      = 10
#   engine                 = "mysql"
#   instance_class         = "db.t2.micro"
#   name                   = "${var.user}DemoDB"
#   username               = var.aws_instance_username
#   password               = var.aws_instance_password
#   vpc_security_group_ids = [aws_security_group.default.id]
#   db_subnet_group_name   = module.vpc.database_subnet_group
#   skip_final_snapshot    = true
# }

resource "aws_db_instance" "oracle" {
  allocated_storage      = 50
  allow_major_version_upgrade = true
  engine                 = "oracle-ee"
  engine_version         = "12.1.0.2.v20"
  instance_class         = "db.m5.large"
  name                   = "mtharpe"
  username               = var.aws_instance_username
  password               = var.aws_instance_password
  vpc_security_group_ids = [aws_security_group.default.id]
  db_subnet_group_name   = module.vpc.database_subnet_group
  skip_final_snapshot    = true
}