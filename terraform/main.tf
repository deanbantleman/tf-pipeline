provider "aws" {
  region = "eu-west-2"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_vpc" "minimal" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "minimal"
  }
}

resource "aws_subnet" "minimal_subnet" {
  vpc_id            = aws_vpc.minimal.id
  cidr_block        = var.subnet_id
  availability_zone = "eu-west-2a"

  tags = {
    Name = "minimal-subnet"
  }
}

resource "aws_instance" "example" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.minimal_subnet.id
  tags = {
    Name = "example_ec2_instance"
  }
}