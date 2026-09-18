data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "windows" {
  most_recent = true
  owners      = var.ami_owners

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  # A NAT gateway only makes sense when the instance itself has no public
  # IP; if enable_public_ip is true the instance subnet already routes
  # straight to the internet gateway.
  need_nat_gateway = var.enable_nat_gateway && !var.enable_public_ip
  need_igw         = var.enable_public_ip || local.need_nat_gateway

  admin_password = coalesce(var.admin_password, try(random_password.admin[0].result, null))

  bootstrap_script = templatefile("${path.module}/scripts/bootstrap.ps1.tftpl", {
    ssh_public_key         = var.ssh_public_key
    admin_password         = local.admin_password
    additional_mounts_json = jsonencode(var.additional_mounts)
  })
}

resource "random_password" "admin" {
  count = var.admin_password == null ? 1 : 0

  length      = 24
  special     = true
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
  # Windows local account passwords reject some special characters.
  override_special = "!#%&*+-.:=?@^_"
}

# --- Networking -------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_subnet" "app" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.name_prefix}-subnet" })
}

resource "aws_internet_gateway" "this" {
  count = local.need_igw ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

# --- NAT path (private instance, but still wants outbound internet) --------

resource "aws_subnet" "nat" {
  count = local.need_nat_gateway ? 1 : 0

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.nat_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-nat-subnet" })
}

resource "aws_eip" "nat" {
  count = local.need_nat_gateway ? 1 : 0

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  count = local.need_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.nat[0].id
  tags          = merge(var.tags, { Name = "${var.name_prefix}-nat" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "nat_subnet" {
  count = local.need_nat_gateway ? 1 : 0

  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-nat-subnet-rt" })
}

resource "aws_route_table_association" "nat_subnet" {
  count = local.need_nat_gateway ? 1 : 0

  subnet_id      = aws_subnet.nat[0].id
  route_table_id = aws_route_table.nat_subnet[0].id
}

# --- App subnet routing ------------------------------------------------

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-rt" })

  dynamic "route" {
    for_each = var.enable_public_ip ? [1] : []
    content {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.this[0].id
    }
  }

  dynamic "route" {
    for_each = local.need_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[0].id
    }
  }
}

resource "aws_route_table_association" "app" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.app.id
}

# --- Security group -----------------------------------------------------

resource "aws_security_group" "this" {
  name_prefix = "${var.name_prefix}-sg-"
  description = "SSH from the admin allow-list only; HTTP/HTTPS for IIS. No RDP/WinRM."
  vpc_id      = aws_vpc.this.id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  count = length(var.admin_source_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "SSH from admin allow-list"
  cidr_ipv4         = var.admin_source_cidr_blocks[count.index]
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  count = length(var.web_source_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "HTTP for IIS"
  cidr_ipv4         = var.web_source_cidr_blocks[count.index]
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  count = length(var.web_source_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "HTTPS for IIS"
  cidr_ipv4         = var.web_source_cidr_blocks[count.index]
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- Compute ------------------------------------------------------------

resource "aws_instance" "this" {
  ami                    = data.aws_ami.windows.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.app.id
  vpc_security_group_ids = [aws_security_group.this.id]
  user_data              = "<powershell>\n${local.bootstrap_script}\n</powershell>"

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  dynamic "cpu_options" {
    for_each = var.cpu_core_count != null ? [1] : []
    content {
      core_count       = var.cpu_core_count
      threads_per_core = var.cpu_threads_per_core
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-vm" })
}

# Additional data volumes - initialized, brought online, and formatted by
# the bootstrap script (see scripts/bootstrap.ps1.tftpl).
resource "aws_ebs_volume" "data" {
  count = length(var.data_disks)

  availability_zone = aws_instance.this.availability_zone
  size              = var.data_disks[count.index].size_gb
  type              = var.data_disks[count.index].type
  encrypted         = true
  tags              = merge(var.tags, { Name = "${var.name_prefix}-data-${count.index}" })
}

resource "aws_volume_attachment" "data" {
  count = length(var.data_disks)

  device_name = "/dev/xvd${substr("fghijklmnop", count.index, 1)}"
  volume_id   = aws_ebs_volume.data[count.index].id
  instance_id = aws_instance.this.id
}

resource "aws_eip" "this" {
  count = var.enable_public_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.this.id
  tags     = merge(var.tags, { Name = "${var.name_prefix}-eip" })

  depends_on = [aws_internet_gateway.this]
}
