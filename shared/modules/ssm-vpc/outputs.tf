output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "igw_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.this.id
}

output "nat_gw_id" {
  description = "ID of the NAT gateway (null if disabled)"
  value       = var.enable_nat_gateway ? aws_nat_gateway.this[0].id : null
}

output "instance_sg_id" {
  description = "ID of the instance security group"
  value       = aws_security_group.instance.id
}

output "public_rt_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_rt_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}
