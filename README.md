# terraform-iam-path

IAM Role의 Path에 따른 S3 버킷 접근 권한 제어 예제입니다.

## 개요

이 프로젝트는 Terraform을 사용하여 IAM Role의 Path(`/dev/` vs `/`)에 따라 S3 버킷의 ListBucket 권한을 다르게 부여하는 방법을 보여줍니다.

- `/dev/` Path Role: S3 버킷 목록 조회 가능
- `/` Path Role: 같은 AdministratorAccess 권한이 있어도 S3 버킷 정책에 의해 접근 차단

## 아키텍처

### IAM Role 구조
```
PATH: /
├── dev/
│   ├── thbins-0   # /dev/ path role
│   └── thbins-1   # /dev/ path role  
└── thbins-2       # / path role (root)
```

### 권한 매트릭스
| Role | Path | Policy | S3 ListBucket |
|------|------|--------|---------------|
| thbins-0 | `/dev/` | AdministratorAccess | ✅ 허용 |
| thbins-1 | `/dev/` | AdministratorAccess | ✅ 허용 |
| thbins-2 | `/` | AdministratorAccess | ❌ 거부 |

## 파일 구성

```
.
├── main.tf       # 모든 리소스 정의
├── README.md     # 이 파일
└── .gitignore
```

## 리소스 구성

### IAM Roles
- **thbins-0, thbins-1**: `/dev/` path, AdministratorAccess 정책
- **thbins-2**: `/` path, AdministratorAccess 정책

### S3 Bucket
- **이름**: 변수로 지정 (`var.bucket_name`)
- **정책**: `/dev/` path role만 ListBucket 허용, 나머지는 명시적 Deny

### 핵심 정책 로직
```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:ListBucket",
  "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME",
  "Condition": {
    "StringNotLike": {
      "aws:PrincipalArn": "arn:aws:iam::*:role/dev/*"
    }
  }
}
```

## 사전 요구사항

- Terraform 1.5+
- AWS CLI (테스트용)
- AWS 자격 증명 구성
- 다음 AWS 권한:
  - IAM Role 생성/관리
  - S3 버킷 생성/정책 설정

> ⚠️ **중요**: S3 버킷 이름은 전역적으로 고유해야 합니다.

## 사용법

### 1. 초기화
```bash
terraform init
```

### 2. 계획 검토
```bash
terraform plan
```

### 3. 배포

**방법 A: CLI에서 직접 지정**
```bash
terraform apply -var="bucket_name=thbinstest1234"
```

**방법 B: terraform.tfvars 파일 사용**

`terraform.tfvars` 파일 생성:
```
bucket_name = "thbinstest1234"
```

그 후 실행:
```bash
terraform apply
```

**방법 C: 대화형 입력**

변수 없이 실행하면 Terraform이 버킷 이름을 물어봅니다:
```bash
terraform apply
# var.bucket_name
#   S3 bucket name (must be globally unique)
# 
#   Enter a value: [여기에 입력]
```



## 테스트

### `/dev/` Path Role 테스트 (성공 예상)
```bash
# Role ARN 설정
DEV_ROLE_ARN="arn:aws:iam::<ACCOUNT_ID>:role/dev/thbins-0"

# AssumeRole
aws sts assume-role \
  --role-arn "$DEV_ROLE_ARN" \
  --role-session-name "dev-test" > creds.json

# 자격 증명 설정
export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' creds.json)
export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' creds.json)
export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' creds.json)

# S3 목록 조회 (성공)
aws s3 ls s3://YOUR_BUCKET_NAME
```

### `/` Path Role 테스트 (실패 예상)
```bash
# Role ARN 설정
ROOT_ROLE_ARN="arn:aws:iam::<ACCOUNT_ID>:role/thbins-2"

# AssumeRole
aws sts assume-role \
  --role-arn "$ROOT_ROLE_ARN" \
  --role-session-name "root-test" > creds.json

# 자격 증명 설정
export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' creds.json)
export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' creds.json)
export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' creds.json)

# S3 목록 조회 (AccessDenied 에러)
aws s3 ls s3://YOUR_BUCKET_NAME
```

## 정리

```bash
terraform destroy
```

## 트러블슈팅

### 문제: EntityAlreadyExists / BucketAlreadyExists 에러

**증상:**
```
Error: creating IAM Role (thbins-2): EntityAlreadyExists: Role with name thbins-2 already exists.
Error: creating S3 Bucket (your-bucket-name): BucketAlreadyExists: The requested bucket name is not available
```

**원인:**
- AWS에는 리소스가 존재하지만 Terraform state에는 기록되지 않은 상태
- 이전 apply 실패 후 리소스 구조 변경, 또는 다른 프로젝트에서 생성한 리소스와 이름 충돌

**해결 방법:**

**방법 1: 수동 정리 (권장)**
```bash
# 현재 state 확인
terraform state list

# IAM Role 삭제
aws iam delete-role --role-name thbins-0
aws iam delete-role --role-name thbins-1  
aws iam delete-role --role-name thbins-2

# S3 버킷 삭제 (내용물 먼저 삭제)
aws s3 rm s3://your-bucket-name --recursive
aws s3 rb s3://your-bucket-name

# 다시 apply
terraform apply -var="bucket_name=your-new-bucket-name"
```

**방법 2: Import 후 관리**
```bash
# 기존 리소스를 Terraform state로 가져오기
terraform import aws_iam_role.this[0] thbins-0
terraform import aws_iam_role.this[1] thbins-1
terraform import aws_iam_role.this2 thbins-2
terraform import aws_s3_bucket.test your-bucket-name

# 이제 Terraform으로 정상 관리 가능
terraform destroy
```

### 예방 방법

1. **고유한 리소스 이름 사용**
   ```hcl
   resource "random_pet" "suffix" {}
   
   resource "aws_s3_bucket" "test" {
     bucket = "${var.bucket_name}-${random_pet.suffix.id}"
   }
   ```

2. **Apply 실패 시 주의사항**
   - 리소스 이름이나 구조를 바로 변경하지 말 것
   - 에러 원인만 수정 후 재시도
   - `terraform state list`로 현재 상태 확인

3. **정기적인 State 확인**
   ```bash
   terraform state list
   terraform plan
   ```

## 핵심 포인트

1. **Path 기반 접근 제어**: IAM Role의 Path를 활용한 세밀한 권한 관리
2. **명시적 Deny**: S3 버킷 정책에서 특정 조건 외 모든 접근 차단
3. **조건부 정책**: `StringNotLike` 조건을 사용한 패턴 매칭
4. **관리형 정책 vs 리소스 정책**: IAM 정책과 S3 버킷 정책의 상호작용

이 예제는 AWS에서 Path 기반 권한 분리와 리소스 정책을 통한 세밀한 접근 제어를 구현하는 방법을 보여줍니다.

---

**참고**: 실제 운영 환경에서는 리소스 이름에 환경별 prefix나 random suffix를 사용하여 충돌을 방지하는 것이 좋습니다.