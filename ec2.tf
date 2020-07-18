provider "aws" {
  region = "ap-south-1"
  profile="surbhisahdev508"
}

resource "tls_private_key" "generated_key" {
  algorithm   = "RSA"
  rsa_bits = 2048
}

resource "aws_key_pair" "generated_key" {
  depends_on = [ tls_private_key.generated_key, ]
  key_name   = "sshkey2"
  public_key = tls_private_key.generated_key.public_key_openssh
}


resource "aws_security_group" "allow_http_NFS" {
  name        = "allow_http_NFS"
  description = "Allow http and ssh NFS"
  vpc_id      = "vpc-47f5e82f"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
     from_port  = 0
     to_port    = 0
     protocol   = "-1"
     cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http"
  }
}


resource "aws_instance" "web" {
  depends_on    = [aws_key_pair.generated_key, aws_security_group.allow_http_NFS]
  ami           = "ami-07a8c73a650069cf3"
  instance_type = "t2.micro"
  key_name      = "sshkey2"
  

  security_groups=[ "allow_http_NFS"]
  tags = {
    Name = "teralaunchos"
  }

 connection {
  type  = "ssh"
  user  = "ec2-user"
  private_key = tls_private_key.generated_key.private_key_pem
  host        = aws_instance.web.public_ip
 }

provisioner "remote-exec" {
      inline = [
          "sudo yum install httpd php git -y",
          "sudo systemctl start httpd",
          "sudo systemctl enable httpd",
          
       ]
     }
   
}

resource "aws_s3_bucket" "bucket" {
  bucket = "udpr5"
  force_destroy = true
  acl    = "public-read"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "MYBUCKETPOLICY",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::udpr5/*"
    }
  ]
}
POLICY
    
}







resource "aws_s3_bucket_object" "object" {
  bucket = "udpr5"
  key    = "img"
  source = "C:/Users/SURBHI/Pictures/Screenshot_20190102-165120 (2).png"
  acl   = "public-read"
  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))
  
}

locals{
  s3_origin_id = "aws_s3_bucket.bucket.id"
  depends_on = [aws_s3_bucket.bucket,
		]
}

resource "aws_efs_file_system" "efs" {
 depends_on =  [ aws_security_group.allow_http_NFS,
                aws_instance.web,  ] 
  creation_token = "efs"




  tags = {
    Name = "efs"
  }
}


resource "aws_efs_mount_target" "mount" {
 depends_on =  [ aws_efs_file_system.efs,
                         ] 
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_instance.web.subnet_id                         
  security_groups = ["${aws_security_group.allow_http_NFS.id}"]
}



resource "null_resource" "null-remote-1"  {
 depends_on = [ 
               aws_efs_mount_target.mount,
                  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.generated_key.private_key_pem
    host     = aws_instance.web.public_ip
  }
  provisioner "remote-exec" {
      inline = [
        "sudo echo ${aws_efs_file_system.efs.dns_name}:/var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
        "sudo mount  ${aws_efs_file_system.efs.dns_name}:/  /var/www/html",
        "sudo https://github.com/surbhi508/terraform.png.git > index.php",                                 
        "sudo cp index.php /var/www/html/",                  
      ]
  }

}

resource "aws_cloudfront_origin_access_identity" "origin" {
     comment = "origin access identity"
 }

resource "aws_cloudfront_distribution" "cloudfront" {
  depends_on = [ 
                 aws_s3_bucket_object.object,
                  ]




  origin {
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    s3_origin_config {
           origin_access_identity = aws_cloudfront_origin_access_identity.origin.cloudfront_access_identity_path 
     }
  }




  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "terraform.png"




  logging_config {
    include_cookies = false
    bucket          =  aws_s3_bucket.bucket.bucket_domain_name
    
  }












  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id




    forwarded_values {
      query_string = false




      cookies {
        forward = "none"
      }
    }




    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }




  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id




    forwarded_values {
      query_string = false
   




      cookies {
        forward = "none"
      }
    }




    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"




  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "IN","CA", "GB", "DE"]
    }
  }




  tags = {
    Environment = "production"
  }




  viewer_certificate {
    cloudfront_default_certificate = true
  }

}

resource "null_resource" "null_resource2" {
 depends_on = [ aws_cloudfront_distribution.cloudfront, ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.generated_key.private_key_pem
    host     = aws_instance.web.public_ip
   }
   provisioner "remote-exec" {
      inline = [
      "sudo su << EOF",
      "echo \"<img src='https://${aws_cloudfront_distribution.cloudfront.domain_name}/${aws_s3_bucket_object.object.key }'>\" >> /var/www/html/index.php",
       "EOF"
   ]
 }

}
