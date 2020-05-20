################################################
# Auto Scaling
################################################
resource "aws_launch_template" "coapp_lt" {
  name          = "${var.friendly_name_prefix}-coapp-ec2-asg-lt-primary"
  image_id      = data.aws_ami.coapp_ami.id
  instance_type = var.instance_size
  key_name      = var.ssh_key_pair != "" ? var.ssh_key_pair : ""
  user_data     = data.template_cloudinit_config.coapp_cloudinit.rendered

  iam_instance_profile {
    name = aws_iam_instance_profile.coapp_instance_profile.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 40
    }
  }

  vpc_security_group_ids = [
    aws_security_group.coapp_ec2_allow.id,
    aws_security_group.coapp_outbound_allow.id
  ]

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      { Name = "${var.friendly_name_prefix}-coapp-ec2-primary" },
      { Type = "autoscaling-group" },
      var.common_tags
    )
  }

  tags = merge({ Name = "${var.friendly_name_prefix}-coapp-ec2-launch-template" }, var.common_tags)
}

resource "aws_autoscaling_group" "coapp_asg" {
  name                      = "${var.friendly_name_prefix}-coapp-asg"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  vpc_zone_identifier       = module.coapp-vpc.public_subnets#var.ec2_subnet_ids
  health_check_grace_period = 600
  health_check_type         = "ELB"

  launch_template {
    id      = aws_launch_template.coapp_lt.id
    version = "$Latest"
  }
  target_group_arns = [
    aws_lb_target_group.coapp_tg_443.arn,
    aws_lb_target_group.coapp_tg_8800.arn
  ]
}

################################################
# Load Balancing
################################################
resource "aws_lb" "coapp_alb" {
  name               = "${var.friendly_name_prefix}-coapp-web-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.coapp_alb_allow.id,
    aws_security_group.coapp_outbound_allow.id
  ]

  subnets = module.coapp-vpc.public_subnets#var.alb_subnet_ids

  tags = merge({ Name = "${var.friendly_name_prefix}-coapp-alb" }, var.common_tags)
}

resource "aws_lb_listener" "coapp_listener_443" {
  load_balancer_arn = aws_lb.coapp_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = element(coalescelist(aws_acm_certificate.coapp_cert[*].arn, list(var.tls_certificate_arn)), 0)

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.coapp_tg_443.arn
  }

  depends_on = [aws_acm_certificate.coapp_cert]
}

resource "aws_lb_listener" "coapp_listener_80_rd" {
  load_balancer_arn = aws_lb.coapp_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "coapp_listener_8800" {
  load_balancer_arn = aws_lb.coapp_alb.arn
  port              = 8800
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = element(coalescelist(aws_acm_certificate.coapp_cert[*].arn, list(var.tls_certificate_arn)), 0)

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.coapp_tg_8800.arn
  }

  depends_on = [aws_acm_certificate.coapp_cert]
}

resource "aws_lb_target_group" "coapp_tg_443" {
  name     = "${var.friendly_name_prefix}-coapp-alb-tg-443"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = module.coapp-vpc.vpc_id

  health_check {
    path                = "/_health_check"
    protocol            = "HTTPS"
    matcher             = 200
    healthy_threshold   = 5
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
  }

  tags = merge(
    { Name = "${var.friendly_name_prefix}-coapp-alb-tg-443" },
    { Description = "ALB Target Group for coapp web application HTTPS traffic" },
    var.common_tags
  )
}

resource "aws_lb_target_group" "coapp_tg_8800" {
  name     = "${var.friendly_name_prefix}-coapp-alb-tg-8800"
  port     = 8800
  protocol = "HTTPS"
  vpc_id   = module.coapp-vpc.vpc_id

  health_check {
    path     = "/authenticate"
    protocol = "HTTPS"
    matcher  = 200
  }

  tags = merge(
    { Name = "${var.friendly_name_prefix}-coapp-alb-tg-8800" },
    { Description = "ALB Target Group for coapp/Replicated web admin console traffic over port 8800" },
    var.common_tags
  )
}