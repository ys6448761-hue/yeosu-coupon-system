# Yeosu Coupon System

QR 코드 기반 쿠폰 시스템

## 구조

```
yeosu-coupon-system/
├── src/
│   ├── api/
│   │   └── coupons.js       # 쿠폰 API 엔드포인트
│   ├── utils/
│   │   └── qrCode.js        # QR 코드 생성 유틸리티
│   ├── app.js               # Express 앱 설정
│   └── server.js            # 서버 진입점
├── database/
│   └── migrations/
│       └── 001_create_tables.sql  # 데이터베이스 스키마
├── .env                     # 환경 변수
├── .gitignore
├── package.json
└── README.md
```

## 환경 설정

`.env` 파일에 다음 변수를 설정하세요:

```
DATABASE_URL=postgresql://...
ENCRYPTION_KEY=...
PORT=8080
```

## 설치

```bash
npm install
```

## 실행

```bash
npm start        # 프로덕션
npm run dev      # 개발 모드
```

## 기능

- QR 코드 기반 쿠폰 생성
- PostgreSQL 데이터베이스 연동
- 암호화된 쿠폰 데이터
