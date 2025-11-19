data "aws_caller_identity" "this" {}

# IAM Role
resource "aws_iam_role" "this" {
    count = 2
    name = "thbins-${count.index}"
    path = "/dev/"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = {
                    AWS = "${data.aws_caller_identity.this.arn}"
                }
            },
        ]
    })
    managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

resource "aws_iam_role" "this2" {
    name = "thbins-2"
    path = "/"
    assume_role_policy  = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = {
                    AWS = "${data.aws_caller_identity.this.arn}"
                }
            },
        ]
    })
    managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

# S3
variable "bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
}

resource "aws_s3_bucket" "test" {
  bucket = var.bucket_name
}

data "aws_iam_policy_document" "test_bucket" {
  statement {
    sid    = "Statement1"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.test.arn,
      "${aws_s3_bucket.test.arn}/*",
    ]

    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"

      values = [
        # 여기서 account_id를 하드코딩하지 않고 자동으로 맞춰줌
        "arn:aws:iam::${data.aws_caller_identity.this.account_id}:role/dev/*",
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "test" {
  bucket = aws_s3_bucket.test.id
  policy = data.aws_iam_policy_document.test_bucket.json
}

/*

Test S3 Bucket의 정책 (Deny 기반으로)

{
 "Version":"2012-10-17",
 "Statement":[
   {
    "Sid":"Statement1",
    "Effect":"Deny",
    "Principal":{
     "AWS":"*"
    },
    "Action":"s3:ListBucket",
    "Resource":[
     "arn:aws:s3:::thbinstest1234",
     "arn:aws:s3:::thbinstest1234/*"
    ],
    "Condition":{
     "StringNotLike":{
      "aws:PrincipalArn":[
        "arn:aws:iam::776698784858:role/dev/*"
      ]
     }
    }
   }
 ]
}


*/