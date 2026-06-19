locals {
  # Lifecycle policy applied to every repository:
  #   Rule 1 (priority 1): expire untagged images after 7 days — keeps storage clean during CI churn
  #   Rule 2 (priority 2): keep only the 10 most recent tagged images — bounds long-term storage cost
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

resource "aws_ecr_repository" "service" {
  for_each = toset(var.service_names)

  # Repository naming: petclinic-{env}/{service-name}
  # e.g. petclinic-dev/api-gateway, petclinic-prod/customers-service
  name                 = "${var.project}-${var.environment}/${each.value}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    # Scan every image on push — surfaces CVEs before they reach EKS nodes
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    {
      Service = each.value
    },
    var.tags
  )
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name
  policy     = local.lifecycle_policy
}
