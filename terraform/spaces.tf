# ABOUTME: Public DigitalOcean Spaces bucket for web assets (page images, meetup
# banners, and other public-facing files). Reads are public; writes require the
# Spaces access key. Terraform state itself lives sops-encrypted in git (no remote
# backend), so this bucket is ordinary infra -- NOT self-referential.

resource "digitalocean_spaces_bucket" "assets" {
  name   = var.assets_bucket_name
  region = var.region

  # Object-level public read is granted by the bucket policy below, not the ACL,
  # so there's no anonymous bucket listing -- only direct-URL GETs.
  acl = "private"
}

resource "digitalocean_spaces_bucket_cors_configuration" "assets" {
  bucket = digitalocean_spaces_bucket.assets.name
  region = digitalocean_spaces_bucket.assets.region

  cors_rule {
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    max_age_seconds = 3600
  }
}

# Anonymous GET on every object (so assets load in a browser), but no listing.
resource "digitalocean_spaces_bucket_policy" "assets_public_read" {
  region = digitalocean_spaces_bucket.assets.region
  bucket = digitalocean_spaces_bucket.assets.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::${digitalocean_spaces_bucket.assets.name}/*"
    }]
  })
}
