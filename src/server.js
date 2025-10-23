// /src/server.js
const app = require('./app');
const PORT = process.env.PORT || 8080;

app.listen(PORT, () => {
  console.log(`🚀 여수여행센터 쿠폰 시스템 API 서버 실행 중...`);
  console.log(`📍 포트: ${PORT}`);
  console.log(`🌐 환경: ${process.env.NODE_ENV || 'development'}`);
  console.log(`📊 데이터베이스: ${process.env.DATABASE_URL ? '연결됨' : '미설정'}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('🛑 SIGTERM 신호를 받았습니다. 서버를 종료합니다...');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('🛑 SIGINT 신호를 받았습니다. 서버를 종료합니다...');
  process.exit(0);
});
