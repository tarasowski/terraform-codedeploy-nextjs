provider "aws" {
  region = var.aws_region
}

provider "archive" {
}

resource "random_pet" "name" {
  length    = 2
  separator = "-"
}

resource "aws_s3_bucket" "deployment_bucket" {
  bucket = random_pet.name.id

  tags = {
    Name = var.name_tag
  }
}

resource "aws_codedeploy_app" "starter" {
  name = var.name_tag
}

resource "aws_codedeploy_deployment_group" "starter" {
  app_name              = aws_codedeploy_app.starter.name
  deployment_group_name = var.name_tag
  service_role_arn      = aws_iam_role.codedeploy.arn

  autoscaling_groups = [aws_autoscaling_group.example.name]

  deployment_config_name = "CodeDeployDefault.OneAtATime"

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Name"
      type  = "KEY_AND_VALUE"
      value = var.name_tag
    }
  }
}

resource "aws_iam_role" "codedeploy" {
  name = "codedeploy-role-custom"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "codedeploy.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "ec2_policy"
  role = aws_iam_role.codedeploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "ec2:*"
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "autoscaling" {
  name = "autoscaling-policy"
  role = aws_iam_role.codedeploy.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:CompleteLifecycleAction",
        "autoscaling:RecordLifecycleActionHeartbeat",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeLifecycleHooks",
        "autoscaling:DeleteLifecycleHook",
        "autoscaling:PutLifecycleHook"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codedeploy" {
  name   = "s3-policy"
  role   = aws_iam_role.codedeploy.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:Get*",
        "s3:List*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_autoscaling_group" "example" {
  availability_zones = var.availability_zones
  name_prefix        = var.name_tag

  launch_configuration = aws_launch_configuration.example.name

  min_size = 1
  max_size = 1
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80 
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}


resource "aws_launch_configuration" "example" {
  name_prefix   = var.name_tag
  image_id      = var.instance_ami
  instance_type = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.s3_access_profile.name

  key_name = var.pem_key
  security_groups    = [aws_security_group.allow_ssh.id]
  user_data = file("user_data.sh")

}

/* notification event to start deployment */


data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "lambda_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../codedeploy/triggers/lambda.js"
  output_path = "lambda_function_payload.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "policy" {
  name = "codedeploy_policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:GetApplicationRevision"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}


resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


resource "aws_lambda_function" "example" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "${var.name_tag}-deployment-trigger"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda.handler"
  runtime       = "nodejs20.x"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      APPLICATION_NAME     =  aws_codedeploy_app.starter.name
      DEPLOYMENT_GROUP_NAME = var.name_tag
    }
  }
}


resource "time_sleep" "wait" {
  depends_on = [aws_lambda_permission.allow_bucket]
  create_duration = "3s"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.deployment_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.example.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [
    time_sleep.wait,
    aws_lambda_function.example,
    aws_lambda_permission.allow_bucket,
  ]
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.example.function_name
  principal     = "s3.amazonaws.com"
  #source_arn    = "${aws_s3_bucket.deployment_bucket.arn}/*"
  source_arn    = "arn:aws:s3:::*"

}

/* attach the role to the instance profile */

# Create the IAM role
resource "aws_iam_role" "s3_access_role" {
  name = "s3_access_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Effect = "Allow",
      },
    ]
  })
}

# Attach the S3 access policy to the role
resource "aws_iam_role_policy" "s3_access_policy" {
  name = "s3_access_policy"
  role = aws_iam_role.s3_access_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}

# Create the instance profile that will be used by the EC2 instances
resource "aws_iam_instance_profile" "s3_access_profile" {
  name = "s3_access_profile"
  role = aws_iam_role.s3_access_role.name
}