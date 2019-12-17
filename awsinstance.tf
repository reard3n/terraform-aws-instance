provider "aws" {
  region   = "us-east-2"
}

terraform {
  backend "s3" {
    bucket  = "dgibbons-tf-statetwo"
    key     = "tfstate"
    region  = "us-east-1"
  }
}


resource "aws_key_pair" "deployer" {
  key_name   = "deployer"
  public_key = file("/Users/dave/Desktop/tftest/id_rsa.pub")
}

# create the VPC that this instance will live inside of
resource "aws_vpc" "dgibbons_test" {
  cidr_block = "172.16.24.0/21"

  tags          = {
    Name       = "dgibbons_test"
  }

  #main_route_table    = aws_route_table.dgibbons_test_route_table
}

# create the subnet that we'll use with this instance tied to the vpc above
resource "aws_subnet" "dgibbons_subnet_test"{
  vpc_id        = aws_vpc.dgibbons_test.id
  cidr_block    = "172.16.24.0/24"
  #map_public_ip_on_launch = true
  depends_on    = [aws_internet_gateway.dgibbons_test_gw]
}

# create the internet gateway that this instance will use to access the internet
resource "aws_internet_gateway" "dgibbons_test_gw" {
  vpc_id = aws_vpc.dgibbons_test.id

  tags = {
    Name = "dgibbons_test"
  }
}

resource "aws_route_table" "dgibbons_test_route_table" {
  vpc_id            = aws_vpc.dgibbons_test.id
  #route             {
  #  cidr_block      = "0.0.0.0/0"
  #  gateway_id      = aws_internet_gateway.dgibbons_test_gw.id
  #}
  depends_on        = [aws_internet_gateway.dgibbons_test_gw,aws_subnet.dgibbons_subnet_test]
}
resource "aws_route_table_association" "dgibbons_test_rta" {
  subnet_id         = aws_subnet.dgibbons_subnet_test.id
  route_table_id    = aws_route_table.dgibbons_test_route_table.id
}

resource "aws_route" "dgibbons_test_gw_route" {
  route_table_id    = aws_route_table.dgibbons_test_route_table.id
  destination_cidr_block  = "0.0.0.0/0"
  gateway_id        = aws_internet_gateway.dgibbons_test_gw.id
}

resource "aws_security_group" "dgibbons_test" {
  name              = "dgibbons_test"
  description       = "test_sec_grp"
  vpc_id            = aws_vpc.dgibbons_test.id
}

resource "aws_security_group_rule" "dgibbons_sg_rule_test" {
  security_group_id = aws_security_group.dgibbons_test.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "dgibbons_sg_rule_egress" {
  security_group_id = aws_security_group.dgibbons_test.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
}

# create the eip that we'll use for this resource
resource "aws_eip" "dgibbons_eip_test" {
  #instance = aws_instance.example.id
  vpc      = true
  depends_on        = [aws_internet_gateway.dgibbons_test_gw]
}

# assign the eip to the instance_type
resource "aws_eip_association" "dgibbons_test_assoc" {
  instance_id = aws_instance.example.id
  allocation_id = aws_eip.dgibbons_eip_test.id
}

resource "aws_instance" "example" {
  ami         = "ami-0d5d9d301c853a04a"
  instance_type = "t2.nano"
  key_name = aws_key_pair.deployer.key_name
  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "100"
  }

  # reference the subnet id created in the previous step that configured our vpc_id
  subnet_id = aws_subnet.dgibbons_subnet_test.id
  vpc_security_group_ids    = [aws_security_group.dgibbons_test.id]

  tags = {
    name = "dgibbons_test_instance"
  }

  depends_on = [aws_internet_gateway.dgibbons_test_gw,aws_route_table.dgibbons_test_route_table]

}

# the provisioner seems to block eip assignment waiting for the provisioner to run (circular dependency). extracting it fixed that issue.
resource "null_resource" "provision_instance" {
  provisioner "remote-exec" {
    connection {
        type        = "ssh"
        user        = "ubuntu"
        #host        = aws_instance.example.public_ip
        host        = aws_eip.dgibbons_eip_test.public_ip
        private_key = file("id_rsa")
      }

      # just run some commands to prove that the provisioner is firing
    inline = [
      "sudo apt-get -y install git",
      "echo 123 > /home/ubuntu/dave.txt",
      "git clone https://github.com/reard3n/vault-consul-monitoring",
      "exit 0"
    ]
  }
  depends_on = [aws_instance.example, aws_eip.dgibbons_eip_test]
}
