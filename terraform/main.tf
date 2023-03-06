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


resource "aws_instance" "example" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  subnet_id     = "subnet-02e5b7a43cd28220c"
  tags = {
    Name = "example_ec2_instance",
    Terraform = "true"
    Department = "CloudOffice"
  }
}

resource "aws_instance" "demo" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  subnet_id     = "subnet-02e5b7a43cd28220c"
  tags = {
    Name = "demo_instance_tsb",
    Terraform = "true"
    Department = "CloudOffice"
  }
}
