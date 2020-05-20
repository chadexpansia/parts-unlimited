data "aws_availability_zones" "azs" {
  #provider = data.aws_region.current.name
  state = "available"
}

resource "aws_subnet" "app" {
  vpc_id     = var.app-vpc
  cidr_block = "10.2.0.0/24"

  tags = {
    Name = "app"
  }
}